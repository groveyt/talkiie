# Third-party notices — Talkiie (public edition)

This file is the public edition's own notices (`app.yyt.talkiie`, plan/decisions/0018). It is bundled into
`Talkiie.app/Contents/Resources/THIRD_PARTY_NOTICES.md` by the TalkiiePublic target (project.yml); the family
edition keeps its own copy at the repository root. `tools/check-release-build.sh --product public` refuses a
build whose bundled copy is missing any of the sections below.

Talkiie transcribes speech on your Mac. The speech model is not inside the app: it is downloaded on first
launch, and its licence and modification notice are stored next to it as well as reproduced here.

## whisper.cpp and ggml

Speech recognition runs on this Mac with whisper.cpp and its ggml tensor library
(https://github.com/ggml-org/whisper.cpp, v1.8.4, commit `9386f239401074690479731c1e41683fbbeac557`),
compiled into the app as a static library (Vendor/whisper/provenance.json). Changed by Talkiie: two patches,
`tools/whisper/reuse-lang-encode.patch` (automatic language detection reuses its encoder pass) and
`tools/whisper/init-state-zero-batch.patch` (an upstream crash fix in `whisper_init_state`'s error paths). The ggml
sources include the YaRN RoPE scaling code, "MIT licensed. Copyright (c) 2023 Jeffrey Quesnelle and Bowen Peng."

```
MIT License

Copyright (c) 2023-2026 The ggml authors

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

## Breeze-ASR-25 (speech model)

The speech model is Breeze-ASR-25 by MediaTek Research (https://huggingface.co/MediaTek-Research/Breeze-ASR-25,
revision `cffe7ccb404d025296a00758d0a33468bec3a9d0`), licensed under the Apache License, Version 2.0.
The upstream repository has no NOTICE file.

**Modified files (Apache License 2.0, Section 4(b)).** The model files Talkiie downloads are MODIFIED versions
of Breeze-ASR-25, made by the Talkiie project with `tools/models/breeze/build.sh`:

- `ggml-breeze-asr-25-q5_0.bin`: `model.safetensors` converted to the whisper.cpp GGML format (f16) with
  whisper.cpp v1.8.4 `models/convert-h5-to-ggml.py`, then quantized to q5_0 with whisper.cpp v1.8.4
  `whisper-quantize`. Quantization changes the weights.
- `ggml-breeze-asr-25-encoder.mlmodelc`: the encoder weights only, converted to a Core ML ML Program
  (float16 weights) with coremltools and whisper.cpp v1.8.4 `models/convert-whisper-to-coreml.py`, then
  compiled with `xcrun coremlc`. The decoder is not included.

These files are not provided or endorsed by MediaTek Research. "Breeze" is used only to describe the origin
of the model (Apache License 2.0, Section 6). Breeze-ASR-25 is fine-tuned from OpenAI Whisper large-v2
(MIT License, next section).

The Breeze-ASR-25 LICENSE file, verbatim (the full Apache License 2.0 text):

```
---
title: Apache License 2.0
spdx-id: Apache-2.0
redirect_from: /licenses/apache/
featured: true
hidden: false

description: A permissive license whose main conditions require preservation of copyright and license notices. Contributors provide an express grant of patent rights. Licensed works, modifications, and larger works may be distributed under different terms and without source code.

how: Create a text file (typically named LICENSE or LICENSE.txt) in the root of your source code and copy the text of the license into the file.

note: The Apache Software Foundation <a href="https://apache.org/foundation/license-faq.html#Apply-My-Software">recommends</a> taking the additional step of adding a boilerplate notice to the header of each source file. You can find the notice in the appendix at the very end of the license text.

using:
  Kubernetes: https://github.com/kubernetes/kubernetes/blob/master/LICENSE
  PDF.js: https://github.com/mozilla/pdf.js/blob/master/LICENSE
  Swift: https://github.com/apple/swift/blob/main/LICENSE.txt

permissions:
  - commercial-use
  - modifications
  - distribution
  - patent-use
  - private-use

conditions:
  - include-copyright
  - document-changes

limitations:
  - trademark-use
  - liability
  - warranty

---

                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright [yyyy] [name of copyright owner]

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
```

## OpenAI Whisper (base model of Breeze-ASR-25)

Breeze-ASR-25 is fine-tuned from the Whisper large-v2 model (https://github.com/openai/whisper). The app also bundles
the 50256 text tokens of Whisper's multilingual tokenizer (`whisper/assets/multilingual.tiktoken`, re-encoded by
`tools/whisper-tokens/build-vocab.py` into NaturalInputCore's `WhisperTokenizer/whisper-vocab.bin`), used on this Mac
only to count how many tokens the personal-dictionary prompt takes. Its LICENSE:

```
MIT License

Copyright (c) 2022 OpenAI

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

## Sparkle 2.10.0

Automatic updates from https://talkiie.yyt.app (`Contents/Frameworks/Sparkle.framework`, https://github.com/sparkle-project/Sparkle,
decisions/0018; same version and same restrictions as decisions/0012 D3). Embedded unmodified except that its XPC services, headers and module maps are removed
(`tools/sparkle-embed.sh`) and it is re-signed with our identity. Its LICENSE file, verbatim:

```
Copyright (c) 2006-2013 Andy Matuschak.
Copyright (c) 2009-2013 Elgato Systems GmbH.
Copyright (c) 2011-2014 Kornel Lesiński.
Copyright (c) 2015-2017 Mayur Pawashe.
Copyright (c) 2014 C.W. Betts.
Copyright (c) 2014 Petroules Corporation.
Copyright (c) 2014 Big Nerd Ranch.
All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=================
EXTERNAL LICENSES
=================

bspatch.c and bsdiff.c, from bsdiff 4.3 <http://www.daemonology.net/bsdiff/>:

Copyright 2003-2005 Colin Percival
All rights reserved

Redistribution and use in source and binary forms, with or without
modification, are permitted providing that the following conditions 
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

--

sais.c and sais.h, from sais-lite (2010/08/07) <https://sites.google.com/site/yuta256/sais>:

The sais-lite copyright is as follows:

Copyright (c) 2008-2010 Yuta Mori All Rights Reserved.

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

--

Portable C implementation of Ed25519, from https://github.com/orlp/ed25519

Copyright (c) 2015 Orson Peters <orsonpeters@gmail.com>

This software is provided 'as-is', without any express or implied warranty. In no event will the
authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial
applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the
   original software. If you use this software in a product, an acknowledgment in the product
   documentation would be appreciated but is not required.

2. Altered source versions must be plainly marked as such, and must not be misrepresented as
   being the original software.

3. This notice may not be removed or altered from any source distribution.

--

SUSignatureVerifier.m:

Copyright (c) 2011 Mark Hamlin.

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted providing that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
```

## OpenCC (Open Chinese Convert)

Taiwan character-variant conversion and a Taiwan vocabulary reference table
(`Sources/NaturalInputCore/TaiwanPhrases.swift`; the vocabulary is not applied to transcripts) use
three dictionary files from https://github.com/BYVoid/OpenCC (`data/dictionary/`, commit
`2939943bd6f4d459b46d7fdcf07a885ab3f01761`, 2026-09-27), bundled unmodified in
`NaturalInput_NaturalInputCore.bundle/OpenCC/`: `TWPhrases.txt`, `TWVariants.txt`,
`TWVariantsPhrases.txt`. Talkiie applies the variant files with its own matcher and leaves a list of
phrases out of the reference table (`TaiwanPhrases.excluded`); the data files themselves are not changed.

The full Apache License 2.0 text is bundled next to the data as `OpenCC/LICENSE`.

```
Copyright (c) 2010-2026 Carbo Kuo and contributors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

## Thinking Orbs

The capsule HUD orb (`Sources/TalkiieOrb/OrbGeometry.swift`) is a Swift port of the
`ribbon` mode (the `composing` state's 64px preset), plus the shared projection / radius
scaling / z-sorting, of https://github.com/Jakubantalik/thinking-orbs (npm `thinking-orbs`
0.3.2). Changes: while listening, the voice level raises the wave, spreads the band's lower
lanes and swells the dots (level 0 is the original); while transcribing, two lights travel
along the band.

```
MIT License

Copyright (c) 2026 Jakub Antalik

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

## Brand artwork (fonts)

The app icon and the menu-bar images are pictures rendered from fonts by `tools/brand/build.sh`
(Assets/brand/fonts/SOURCES.md). No font file is included in the app. The fonts come from the official
google/fonts repository (commit `23e54b51ddffbc7713c583748e3bd86f62b1fa4a`) and are licensed under the
SIL Open Font License 1.1 — Damion (© 2014 The Damion Project Authors; the app icon and idle menu-bar glyph),
UnifrakturMaguntia, Jacquard 12, Plaster, Abril Fatface, Alfa Slab One, Rye, Bungee Outline, Varela Round,
Bebas Neue, Limelight, Michroma, Nosifer, Bangers, Cinzel Decorative, Monoton, Faster One and Ribeye Marrow —
or the Apache License 2.0 — Permanent Marker and Special Elite. Rendering a font into an image is not
a distribution of the font; this section is informational.

## Swift packages

Package.resolved contains exactly one third-party package: Sparkle 2.10.0 (above). Everything else is
Talkiie's own code or Apple system frameworks.

## 小麥注音（McBopomofo）注音資料（McBopomofo bopomofo data, bundled）

**隨 app 散布（1.1.0 起，plan/decisions/0020）。** 用來判斷「注音相近的聽錯字」（設定 › 文字 › 個人詞庫的
「注音相近的錯字也改」，以及從「收集我的修改」自動加詞時判斷是不是聽錯）。只在這台 Mac 上讀，不送出。
來源是 https://github.com/openvanilla/McBopomofo tag `3.1.1`（commit `f5ba010ce8795d283ee336ca7d16380f200bd2ec`），
app 裡收的是從它挑出來、改過格式的子集，在 NaturalInputCore 的資源包 `Bopomofo/` 資料夾：

- `chars.txt`：單字讀音，取自 `Source/Data/BPMFBase.txt` 的注音欄（只留 Big5／CNS 字集內的字，
  以及 `words.txt` 用到的字）。
- `words.txt`：2–4 個字的詞，取自 `Source/Data/phrase.occ` 與 `Source/Data/BPMFMappings.txt`
  （NFC 正規化、只留漢字；不含詞頻、不含讀音）。
- `LICENSE`：下面兩份授權全文，跟資料放在一起。

由 `tools/lexicon/bopomofo-subset/build.sh` 產生。`BPMFMappings.txt` 依上游說明
"Originally simplified from tsi.src of libtabe (BSD Licensed) with modifications"，所以一併附上 libtabe 的聲明。
TaBE Project、中央研究院資訊科學研究所 CSCL 及其貢獻者的名義，不代表對本產品的背書或推廣。
McBopomofo 的作者也沒有建議、認可或贊同 Talkiie。

Shipped in the app since 1.1.0: a modified subset of McBopomofo 3.1.1 (single-character readings from
`Source/Data/BPMFBase.txt`; 2-4 character words from `Source/Data/phrase.occ` and `Source/Data/BPMFMappings.txt`,
NFC-normalized, CJK only, no counts or readings), used on this Mac only to spot misrecognised words that sound alike.

McBopomofo `LICENSE.txt`：

```
MIT License

Copyright (c) 2011-2026 Mengjuei Hsieh et al.

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

libtabe `tsi-src/COPYING`（https://github.com/kcwu/libtabe ，commit `ea382a829c916f2cceda2022afdf8e8471e6e7b5`），原文照錄（含原文的拼字）：

```
/*
 * Copyrighy (c) 1999 TaBE Project.
 * Copyright (c) 1999 Pai-Hsiang Hsiao.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * . Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 * . Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in
 *   the documentation and/or other materials provided with the
 *   distribution.
 * . Neither the name of the TaBE Project nor the names of its
 *   contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * REGENTS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/*
 * Copyright (c) 1999 Computer Systems and Communication Lab,
 *                    Institute of Information Science, Academia Sinica.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * . Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 * . Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in
 *   the documentation and/or other materials provided with the
 *   distribution.
 * . Neither the name of the Computer Systems and Communication Lab
 *   nor the names of its contributors may be used to endorse or
 *   promote products derived from this software without specific
 *   prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * REGENTS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 */

Copyright 1996 Chih-Hao Tsai @ Beckman Institute, University of Illinois
c-tsai4@uiuc.edu  http://casper.beckman.uiuc.edu/~c-tsai4
```

## 參考詞庫與資料（reference lexicons and data）

**現況：開發時參考使用，未隨 app 散布。** 下面這些詞庫與資料只在開發者自己的電腦上，用來驗證簡轉繁與
台灣用語、檢視轉錄結果（`tools/lexicon/`，原始檔在不入庫、不外傳的 `research-data/`）。這個 app 裡**沒有**
這些檔案，也沒有從它們挑出來的詞表。這一段照樣附上出處與授權全文：將來如果有任何一部分（整份或挑出來的
子集）隨 app 出貨，下面的條件同樣適用，出貨前會把它移到自己的段落、寫明用了哪個檔、做了什麼修改。
這些資料的提供者都沒有建議、認可或贊同 Talkiie。
（小麥注音的注音資料從 1.1.0 起有一部分隨 app 散布，見上一段「小麥注音（McBopomofo）注音資料」。）

Status: development reference data only. None of these files, and no word list derived from them, is included
in this app. The notices below are kept here so they remain correct if a subset ships in the future.
(Since 1.1.0 a subset of the McBopomofo data does ship in the app; see the previous section.)

### 教育部《重編國語辭典修訂本》（經由萌典 g0v moedict-data）

姓名標示（依教育部《重編國語辭典修訂本》公眾授權使用說明的格式）：

> 中華民國教育部（Ministry of Education, R.O.C.）。《重編國語辭典修訂本》（版本編號：dict_revised_2015_20260625）網址：http://dict.revised.moe.edu.tw/

依「創用CC 姓名標示－禁止改作 3.0 臺灣」（CC BY-ND 3.0 TW）授權，條款全文：
https://creativecommons.org/licenses/by-nd/3.0/tw/legalcode 。
取得途徑：g0v 萌典 moedict-data（https://github.com/g0v/moedict-data ，commit
`a6dc997417507eb510fc29822bc514de2c92728c`，檔案 `dict-revised.json.xz`）；g0v 的格式轉換與重新編排由
@kcwu 以 CC0 釋出，感謝萌典。開發用的整理版只取出詞目與注音，並做了 Unicode 正規化（NFC）等格式處理，
只在開發者電腦上使用、不散布；沒有、也不會轉成簡化字。目前未隨 app 散布；若將來散布，會另外產生不改動
個別條目內容與碼位的版本，並附上下面這份使用說明。

《重編國語辭典修訂本》公眾授權使用說明（`reviseddict_10312.pdf`，
https://language.moe.gov.tw/001/Upload/Files/site_content/M0001/respub/reviseddict_10312.pdf ）全文照錄
（只把 PDF 段落內的斷行接回）：

```
《重編國語辭典修訂本》公眾授權使用說明
一、授權方式及範圍
(一) 教育部《重編國語辭典修訂本》係受國際著作權公約與中華民國著作權法保護之著作。
(二) 教育部《重編國語辭典修訂本》採用「創用 CC－姓名標示－禁止改作 臺灣 3.0 版授權條款」釋出。此授權條款的內容詳見網址：
http://creativecommons.org/licenses/by-nd/3.0/tw/legalcode
(三) 「姓名標示」部分請標示如下：
中華民國教育部（Ministry of Education, R.O.C.）。《重編國語辭典修訂本》（版本編號： ）網址：http://dict.revised.moe.edu.tw/
(四) 額外授權聲明：
依本著作權利人中華民國教育部（Ministry of Education, R.O.C.）之聲明，任何使用者皆得依照「創用 CC－姓名標示－禁止改作 臺灣 3.0 版授權條款」的規定，使用《重編國語辭典修訂本》之資料與素材。使用者對於《重編國語辭典修訂本》個別條目的詞目、部首、筆畫、字形、音讀及釋義等內容不得為任何修改，或轉為簡化字。惟依教育部所提供對照表內容作字碼改換，或不涉及更改《重編國語辭典修訂本》個別條目所有內容之調整行為，可不被認定構成上述禁止修改條款之拘束範圍。
二、使用者承諾事項
使用者利用教育部公眾授權之《重編國語辭典修訂本》資料與素材，無論再散布與否，都必須完整保留本使用說明，並確認資料版本訊息；如發現原始內容錯誤或遺漏，應同意無償提供完整資訊予教育部於研究及修訂之參考。
三、停止提供
其有下列情形之一者，教育部得隨時停止提供《重編國語辭典修訂本》資料與素材，民眾不得向教育部請求任何賠償或補償，教育部亦不負任何賠償或補償之責任：
(一) 因政策變更或其他正當事由，致教育部認為繼續提供資料供民眾使用，已不符合公共利益之要求。
(二) 教育部公開之資料與素材有侵害第三人智慧財產權、隱私權或其他權利之疑慮。
```

### jieba-zh_TW 詞典（只在開發者電腦上做內部研究，從不散布）

`jieba/dict.txt`，https://github.com/ldkrsi/jieba-zh_TW （commit `38694b9d6d306f1338351a97f2ef942ba6759e75`，
fork 自 https://github.com/fxsjy/jieba ）。**只在開發者自己的電腦上做非營利的內部研究**（例如量測轉錄結果裡
有多少詞在詞表中），**從不散布**：不在任何版本的 app 裡，也不會用來產生任何隨 app 出貨的資料
（個人詞庫建議、語音模型提示詞彙等）。上游要求遵守中央研究院斷詞服務之服務條款
（https://ckipsvr.iis.sinica.edu.tw/terms.htm ）的衍生資料規定：僅供學術研究及非營利用途、不得包含或引用於
商業產品、不得移轉給第三人。依該條款第四點，本專案誌謝**中央研究院資訊科學研究所詞庫小組（CKIP）**。

jieba 的程式碼授權（上游 `LICENSE`）：

```
The MIT License (MIT)

Copyright (c) 2013 Sun Junyi

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

### 政府資料開放平臺：村里、路名、機關代碼

開發時取用下列資料集的名稱欄位（縣市、鄉鎮市區、村里、路街名、現存機關名），整理成詞表；目前未隨 app 散布。
顯名聲明（政府資料開放授權條款－第1版 附件）：

```
內政部戶政司 2026 村里戶數、單一年齡人口（新增區域代碼）11508
內政部戶政司 2026 全國路名資料 115
行政院人事行政總處 2026 行政院所屬中央及地方機關代碼（2026-09-28 取得）
此開放資料依政府資料開放授權條款進行公眾釋出，使用者於遵守本條款各項規定之前提下，得利用之。
政府資料開放授權條款：https://data.gov.tw/license
```

資料集頁面：https://data.gov.tw/dataset/77132 、https://data.gov.tw/dataset/35321 、https://data.gov.tw/dataset/7307 。

### 國家教育研究院「樂詞網」

出處：國家教育研究院「樂詞網」學術名詞（電子計算機名詞、電機工程名詞、通訊工程、醫學名詞、法律學名詞－民法、
法律學名詞－刑法、法律學名詞－公法、經濟學、管理學名詞、會計學、市場學、統計學名詞、心理學名詞、教育學、
新聞傳播學名詞、食品科技、社會學名詞）、外國地名譯名，以及兩岸常用詞語對照表、兩岸一般名詞對照，
https://terms.naer.edu.tw/ ，2026-09-28 下載。依樂詞網「政府網站資料開放宣告」
（https://terms.naer.edu.tw/mysite/about/2/ ）提供之授權使用，應註明出處；該授權不代表國家教育研究院建議、
認可或贊同 Talkiie。開發時只取中文名稱並拆開並列詞與括號註解（不收英文與其他外文欄），目前未隨 app 散布；
兩岸對照表只當開發參考。
