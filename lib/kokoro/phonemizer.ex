defmodule Kokoro.Phonemizer do
  def phonemize(text, lang \\ "en-us") do
    # Extract and store punctuation with their positions
    {text_without_punct, punct_map} = extract_punctuation(text)

    args = build_args(lang)

    port =
      Port.open({:spawn_executable, find_espeak()}, [
        :binary,
        :exit_status,
        args: args ++ [text_without_punct]
      ])

    phonemes = receive do
      {^port, {:data, phonemes}} ->
        phonemes
        |> String.trim()
        |> normalize_phonemes()

      {^port, {:exit_status, 0}} ->
        :ok

      {^port, {:exit_status, status}} ->
        raise "espeak failed with status #{status}"
    end

    # Restore punctuation to the phonemized text
    restore_punctuation(phonemes, punct_map)
  end

  defp build_args(lang) do
    [
      # Quiet mode
      "-q",
      # Use IPA phonetic symbols
      "--ipa",
      # Language/voice selection
      "-v",
      lang
    ]
  end

  defp find_espeak do
    System.find_executable("/opt/homebrew/bin/espeak") ||
      raise "espeak not found in PATH. Please install espeak-ng"
  end

  defp normalize_phonemes(phonemes) do
    phonemes
    # Remove stress numbers in parentheses
    # |> String.replace(~r/\(\d+\)/, "")
    # Normalize whitespace
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  def extract_punctuation(text) do
    punct_regex = ~r/([.,!?;])/
    parts = String.split(text, punct_regex, include_captures: true, trim: true)

    {text_parts, punct_map, _word_count} =
      parts
      |> Enum.reduce({[], %{}, 0}, fn
        punct, {texts, puncts, word_count} when punct in [".", ",", "!", "?", ";"] ->
          {texts, Map.put(puncts, word_count - 1, punct), word_count}
        text, {texts, puncts, word_count} ->
          words = String.split(text, " ", trim: true)
          {texts ++ words, puncts, word_count + length(words)}
      end)

    {Enum.join(text_parts, " "), punct_map}
  end

  def restore_punctuation(phonemes, punct_map) do
    parts = String.split(phonemes, " ", trim: true)

    parts
    |> Enum.with_index()
    |> Enum.map(fn {part, i} ->
      case Map.get(punct_map, i) do
        nil -> part
        punct -> part <> punct
      end
    end)
    |> Enum.join(" ")
  end
end
