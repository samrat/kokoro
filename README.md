# Kokoro

Elixir bindings to the [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) text-to-speech model

## Usage

- Add this library as a mix dependency:

```elixir
# Hex package coming soon
{:kokoro, github: "samrat/kokoro"} 
```

- Download ONNX model from <https://huggingface.co/onnx-community/Kokoro-82M-ONNX/tree/main/onnx>
- Download voice .bin file from <https://huggingface.co/onnx-community/Kokoro-82M-ONNX/tree/main/voices>

Then,

```elixir
kokoro = Kokoro.new("/path/to/kokoro-v0_19.onnx", "/path/to/voices/directory")
Kokoro.save_audio_to_file(kokoro, "Hello from Elixir", "af_nicole", 1.0, "/tmp/output.raw")
```

Convert raw audio to wav

```sh
❯ ffmpeg -f f32le -ar 24000 -ac 1 -i /tmp/output.raw /tmp/output.wav
```

Or,

```elixir
kokoro = Kokoro.new("/path/to/kokoro-v0_19.onnx", "/path/to/voices/directory")
{audio_tensor, _} = Kokoro.create_audio(kokoro, "Hello from Elixir", "af_nicole", 1.0)
wave_data = Kokoro.create_wave(audio_tensor)

```

## TODO

- [ ] Use `espeak` via NIF bindings(?)
- [ ]

MIT License. © [Samrat Man Singh](https://samrat.me)

