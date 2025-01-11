defmodule Kokoro.Phonemizer do
  def phonemize(text, lang \\ "en-us") do
    args = build_args(lang)

    port =
      Port.open({:spawn_executable, find_espeak()}, [
        :binary,
        :exit_status,
        args: args ++ [text]
      ])

    receive do
      {^port, {:data, phonemes}} ->
        phonemes
        |> String.trim()
        |> normalize_phonemes()

      {^port, {:exit_status, 0}} ->
        :ok

      {^port, {:exit_status, status}} ->
        raise "espeak failed with status #{status}"
    end
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
    |> String.replace(~r/\(\d+\)/, "")
    # Normalize whitespace
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end

Kokoro.Phonemizer.phonemize("Hello world")
