defmodule Kokoro do
  require Logger

  defstruct [:session, :voices]

  def new(model_path, voices_path) do
    # Load the ONNX model
    session = Ortex.load(model_path)

    # Load voices from JSON file
    voices =
      voices_path
      |> File.read!()
      |> Jason.decode!()

    # Create Kokoro instance
    %__MODULE__{
      session: session,
      voices: voices
    }
  end

  # TODO: Split text by punctuation and generate audio for each chunk?
  # There is also a max length for the tokens
  def create_audio(kokoro, text, voice, speed \\ 1.0) do
    # Validate inputs
    unless Map.has_key?(kokoro.voices, voice) do
      raise "Voice #{voice} not found in available voices"
    end

    unless speed >= 0.5 and speed <= 2.0 do
      raise "Speed should be between 0.5 and 2.0"
    end

    tokens =
      Kokoro.Phonemizer.phonemize(text) |> dbg()
      |> Kokoro.Tokenizer.tokenize()

    # Prepare inputs for model
    # 0-pad the tokens
    tokens_tensor = Nx.tensor([[0 | tokens ++ [0]]], type: :s64)

    # Take just the first row of style data to get [1, 256] shape
    style_data = Map.get(kokoro.voices, voice)
    style =
      style_data
      # Take first row
      |> List.first()
      # Take first inner array
      |> List.first()
      |> Nx.tensor(type: :f32)
      # Ensure shape is [1, 256]
      |> Nx.reshape({1, 256})

    speed_tensor = Nx.tensor([speed], type: :f32)

    {audio} = Ortex.run(kokoro.session, {tokens_tensor, style, speed_tensor})

    {audio, 24000}
  end

  def save_audio_to_file(kokoro, text, voice, speed, dest_path) do
    {audio_tensor, _sample_rate} = create_audio(kokoro, text, voice, speed)

    audio_binary =
      audio_tensor
      |> Nx.to_flat_list()
      |> Enum.map(fn x -> <<x::float-32-little>> end)
      |> Enum.join()

    File.write!(dest_path, audio_binary)
  end

  def get_voices(%__MODULE__{voices: voices}) do
    Map.keys(voices)
  end
end
