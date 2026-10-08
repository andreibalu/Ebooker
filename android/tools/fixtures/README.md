# Speech fixture

`jfk.wav` is the 11-second, 16 kHz mono PCM sample from
[whisper.cpp v1.9.5](https://github.com/ggml-org/whisper.cpp/blob/v1.9.5/samples/jfk.wav).
It records President John F. Kennedy's 1961 inaugural address, delivered in
his official capacity as a United States federal government employee.
The address is a US government work in the public domain in the United States.
whisper.cpp distributes the sample with its MIT-licensed source archive.

This is only a document-picker E2E fixture. It is outside all Android source-set
assets and is never included in the app APK. The fixture generator prefers locally
synthesized original text through macOS `say`; it uses this recording if synthesis
produces an empty file in a sandbox. The generated file is named `AI Speech.wav`.
Both paths validate mono, PCM16, 16 kHz audio and nonzero duration.

The Kennedy Library's [archival guide](https://static.jfklibrary.org/4xha665323571b53213i287t8gxbt580.pdf?odc=20231115174728-0500)
explains that statements by federal officials in the course of their duties are
in the public domain. The [National Archives inaugural address source](https://docsteach.org/document/jfk-inaugural/)
also labels the address public domain and free of known copyright restrictions.

Fixture SHA-256: `59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e`.
