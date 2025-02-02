defmodule Kokoro do
  require Logger

  defstruct [:session, :voices]

  # Matching Python's MAX_PHONEME_LENGTH
  @max_phoneme_length 510

  # wave file format
  @n_channels 1
  @sampwidth 2
  @frame_rate 24_000

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

    # Combine all audio tensors
    combined_audio = Nx.concatenate(audio_tensors)
    {combined_audio, 24000}
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
              chunks =
                part
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
              [first | rest] =
                part
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
    {audio_tensor, _sample_rate} = create_audio(kokoro, text, voice, speed)

    audio_tensor
    |> Nx.to_binary()
  end

  def get_voices(%__MODULE__{voices: voices}) do
    Map.keys(voices)
  end

  defp normalize_audio_data(tensor) do
    """
    https://github.com/ipython/ipython/blob/5949cc367e5c095a51bf74dbbb7c459617f1d6d7/IPython/lib/display.py#L169
    """

    max_abs_value = tensor |> Nx.abs() |> Nx.reduce_max()

    tensor
    |> Nx.divide(max_abs_value)
    |> Nx.dot(32767)
    |> Nx.round()
    |> Nx.as_type(:u16)
    |> Nx.to_binary()
  end

  def create_wave(tensor) do
    audio_binary = tensor |> Nx.backend_transfer() |> normalize_audio_data()
    audio_size = byte_size(audio_binary)

    # https://www.mmsp.ece.mcgill.ca/Documents/AudioFormats/WAVE/WAVE.html
    <<
      # wave file format
      "RIFF",
      36 + audio_size::32-little,
      "WAVE",

      # fmt chunk
      "fmt ",
      16::32-little,
      1::16-little,
      @n_channels::16-little,
      @frame_rate::32-little,
      @n_channels * @sampwidth * @frame_rate::32-little,
      @n_channels * @sampwidth::16-little,
      @sampwidth * 8::16-little,

      # data chunk
      "data",
      audio_size::32-little,
      audio_binary::binary
    >>
  end

  defp normalize_text(text) do
    text
    # Replace smart quotes
    |> String.replace(["\u2018", "\u2019"], "'")
    |> String.replace("«", "\u2020")
    |> String.replace("»", "\u2021")
    |> String.replace(["\u2020", "\u2021"], "\"")
    |> String.replace("(", "«")
    |> String.replace(")", "»")
    # Replace Chinese/Japanese punctuation with English equivalents
    |> replace_cjk_punctuation()
    # Replace non-space whitespace with space
    |> String.replace(~r/[^\S \n]/, " ")
    # Collapse multiple spaces
    |> String.replace(~r/  +/, " ")
    # Remove spaces between newlines
    |> String.replace(~r/(?<=\n) +(?=\n)/, "")
    |> normalize_titles()
    # |> normalize_numbers()
    |> String.trim()
  end

  defp replace_cjk_punctuation(text) do
    replacements = [
      {"、", "., "},
      {"。", ". "},
      {"！", "! "},
      {"，", ", "},
      {"：", ": "},
      {"；", "; "},
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
