defmodule Kokoro.Tokenizer do
  @pad "$"
  @punctuation ";:,.!?¡¿—…\"«»“” "
  @letters "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  @letters_ipa "ɑɐɒæɓʙβɔɕçɗɖðʤəɘɚɛɜɝɞɟʄɡɠɢʛɦɧħɥʜɨɪʝɭɬɫɮʟɱɯɰŋɳɲɴøɵɸθœɶʘɹɺɾɻʀʁɽʂʃʈʧʉʊʋⱱʌɣɤʍχʎʏʑʐʒʔʡʕʢǀǁǂǃˈˌːˑʼʴʰʱʲʷˠˤ˞↓↑→↗↘'̩'ᵻ"

  @vocab ([@pad] ++
            String.graphemes(@punctuation) ++
            String.graphemes(@letters) ++
            String.graphemes(@letters_ipa))
         |> Enum.with_index()
         |> Map.new()

  @max_phoneme_length 512

  def tokenize(phonemes) when is_binary(phonemes) do
    if String.length(phonemes) > @max_phoneme_length do
      raise "text is too long, must be less than #{@max_phoneme_length} phonemes"
    end

    phonemes
    |> String.graphemes()
    |> Enum.map(&Map.get(@vocab, &1))
    |> Enum.reject(&is_nil/1)
  end

  def get_vocab, do: @vocab
end
