defmodule Kokoro do
  require Logger

  defstruct [:session, :voices]

  @max_phoneme_length 510  # Matching Python's MAX_PHONEME_LENGTH

  def new(model_path, voices_dir) do
    # Load the ONNX model
    session = Ortex.load(model_path)

    # Load voices from .bin files in the voices directory
    voices =
      voices_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".bin"))
      |> Map.new(fn filename ->
        voice_name = Path.basename(filename, ".bin")
        voice_path = Path.join(voices_dir, filename)
        voice_data = load_voice_binary(voice_path)
        {voice_name, voice_data}
      end)

    # Create Kokoro instance
    %__MODULE__{
      session: session,
      voices: voices
    }
  end

  defp load_voice_binary(path) do
    data =
      path
      |> File.read!()
      |> then(fn binary ->
        binary
        |> :binary.bin_to_list()
        |> Enum.chunk_every(4)
        |> Enum.map(fn bytes ->
          <<float::float-32-little>> = :erlang.list_to_binary(bytes)
          float
        end)
      end)
      |> Enum.chunk_every(256)
      |> Enum.map(&List.wrap/1)

    [data]
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

    normalized_text = normalize_text(text)

    # Get phonemes and split into batches
    phonemes = Kokoro.Phonemizer.phonemize(normalized_text)
    phoneme_batches = split_phonemes(phonemes)

    # Process each batch and concatenate results
    audio_tensors =
      Enum.map(phoneme_batches, fn batch_phonemes ->
        tokens =
          batch_phonemes
          |> Kokoro.Tokenizer.tokenize()

        # Prepare inputs for model
        tokens_tensor = Nx.tensor([[0 | tokens ++ [0]]], type: :s64)
        style_data = Map.get(kokoro.voices, voice)
        style =
          style_data
          |> List.first()
          |> List.first()
          |> Nx.tensor(type: :f32)
          |> Nx.reshape({1, 256})

        speed_tensor = Nx.tensor([speed], type: :f32)

        {audio} = Ortex.run(kokoro.session, {tokens_tensor, style, speed_tensor})
        audio
      end)

    {audio_tensors, 24000}
  end

  defp split_phonemes(phonemes) do
    # Split by punctuation marks while keeping them
    phonemes
    |> String.split(~r/([.,!?;])/, include_captures: true, trim: true)
    |> Enum.chunk_while(
      "",
      fn part, acc ->
        part = String.trim(part)
        new_length = String.length(acc) + String.length(part) + 1

        cond do
          part == "" ->
            {:cont, acc}
          new_length > @max_phoneme_length and acc != "" ->
            if String.length(part) > @max_phoneme_length do
              # If the part itself is too long, split it into chunks of max_length
              chunks = part
                |> String.graphemes()
                |> Enum.chunk_every(@max_phoneme_length)
                |> Enum.map(&Enum.join/1)

              # Output the accumulated string first
              {:cont, String.trim(acc), List.first(chunks)}
            else
              {:cont, String.trim(acc), part}
            end
          String.match?(part, ~r/^[.,!?;]$/) ->
            {:cont, acc <> part}
          acc == "" ->
            if String.length(part) > @max_phoneme_length do
              # Split long initial part into chunks
              [first | rest] = part
                |> String.graphemes()
                |> Enum.chunk_every(@max_phoneme_length)
                |> Enum.map(&Enum.join/1)
              {:cont, first, List.first(rest) || ""}
            else
              {:cont, part}
            end
          true ->
            {:cont, acc <> " " <> part}
        end
      end,
      fn
        "" -> {:cont, []}
        acc -> {:cont, String.trim(acc), []}
      end
    )
  end

  def save_audio_to_file(kokoro, text, voice, speed, dest_path) do
    audio_binary = create_audio_binary(kokoro, text, voice, speed)
    File.write!(dest_path, audio_binary)
  end

  def create_audio_binary(kokoro, text, voice, speed) do
    {audio_tensors, _sample_rate} = create_audio(kokoro, text, voice, speed)

    audio_tensors
    |> Enum.flat_map(fn tensor ->
      tensor
      |> Nx.to_flat_list()
      |> Enum.map(fn x -> <<x::float-32-little>> end)
    end)
    |> Enum.join()
  end

  def get_voices(%__MODULE__{voices: voices}) do
    Map.keys(voices)
  end

  defp normalize_text(text) do
    text
    |> String.replace(["\u2018", "\u2019"], "'") # Replace smart quotes
    |> String.replace("«", "\u2020")
    |> String.replace("»", "\u2021")
    |> String.replace(["\u2020", "\u2021"], "\"")
    |> String.replace("(", "«")
    |> String.replace(")", "»")
    # Replace Chinese/Japanese punctuation with English equivalents
    |> replace_cjk_punctuation()
    |> String.replace(~r/[^\S \n]/, " ") # Replace non-space whitespace with space
    |> String.replace(~r/  +/, " ") # Collapse multiple spaces
    |> String.replace(~r/(?<=\n) +(?=\n)/, "") # Remove spaces between newlines
    |> normalize_titles()
    # |> normalize_numbers()
    |> String.trim()
  end

  defp replace_cjk_punctuation(text) do
    replacements = [
      {"、", "., "}, {"。", ". "}, {"！", "! "},
      {"，", ", "}, {"：", ": "}, {"；", "; "},
      {"？", "? "}
    ]
    Enum.reduce(replacements, text, fn {from, to}, acc ->
      String.replace(acc, from, to)
    end)
  end

  defp normalize_titles(text) do
    text
    |> String.replace(~r/\bD[Rr]\.(?= [A-Z])/, "Doctor")
    |> String.replace(~r/\b(?:Mr\.|MR\.(?= [A-Z]))/, "Mister")
    |> String.replace(~r/\b(?:Ms\.|MS\.(?= [A-Z]))/, "Miss")
    |> String.replace(~r/\b(?:Mrs\.|MRS\.(?= [A-Z]))/, "Mrs")
    |> String.replace(~r/\betc\.(?! [A-Z])/, "etc")
  end

end
