# Kokoro

Elixir bindings to Kokoro-82M(https://huggingface.co/hexgrad/Kokoro-82M)

## TODO
- [ ] Use `espeak` via NIF bindings(?)
- [ ] 

## Usage

- Download onnx model from https://huggingface.co/onnx-community/Kokoro-82M-ONNX/tree/main/onnx
- Download voice .bin file from https://huggingface.co/onnx-community/Kokoro-82M-ONNX/tree/main/voices

Then,

```elixir
kokoro = Kokoro.new("/path/to/kokoro-v0_19.onnx", "/path/to/voices/directory")
Kokoro.save_audio_to_file(kokoro, "Hello from Elixir", "af_nicole", 1.0, "/tmp/output.raw")
```

Convert raw audio to wav

```sh
❯ ffmpeg -f f32le -ar 24000 -ac 1 -i /tmp/output.raw /tmp/output.wav
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `kokoro_tts` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:kokoro_tts, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/kokoro_tts>.

