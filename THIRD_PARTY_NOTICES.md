# Third-party notices

## thibaultmiclo/aula-driver

AULA Studio's S75 Pro protocol encoders (`Sources/AulaCore/S75Protocol.swift`, `ScreenEncoder.swift`) are a Swift port of the packet formats and transaction order in [thibaultmiclo/aula-driver](https://github.com/thibaultmiclo/aula-driver), and `Sources/SelfCheck` uses expected bytes from its test suite.

```
MIT License

Copyright (c) 2026 aula-driver contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## OpenRGB

The F75 Pro's direct-lighting commands were first documented by OpenRGB's `SinowealthKeyboard10c` controller (GPL-2.0-or-later). AULA Studio contains no OpenRGB code: it implements the documented protocol independently.

## AULA

The key layouts in `Sources/AulaCore/Layouts.swift` were generated from configuration files in AULA's Windows installers. Those files aren't redistributed here. AULA is a trademark of its owner. This project is not affiliated with AULA.
