---
name: security
description: ตรวจความปลอดภัยของโปรเจค — ตรวจจับเองว่าเป็น web app, เกม (Unity/Godot/Unreal), mobile app (Android/iOS/Flutter/React Native) หรือหลายอย่างรวมกัน แล้วรันเครื่องมือสแกนและรีวิวโค้ดตาม checklist ของแพลตฟอร์มนั้น ใช้เมื่อผู้ใช้พิมพ์ /security หรือขอให้ตรวจ security หรือหาช่องโหว่ของโปรเจค
argument-hint: "[full | diff | quick | setup]"
allowed-tools: Read, Grep, Glob, Write, Bash(semgrep:*), Bash(gitleaks:*), Bash(trivy:*), Bash(mobsfscan:*), Bash(jq:*), Bash(git diff:*), Bash(git log:*), Bash(git status:*), Bash(git rev-parse:*), Bash(git ls-files:*), Bash(git merge-base:*), Bash(git symbolic-ref:*), Bash(mkdir -p .security:*), Bash(date:*)
---

# /security — Project Security Audit

## โหมด
argument ที่ได้รับ: `$ARGUMENTS` (ถ้าว่าง ให้ใช้ `full`)

- `full`: สแกนทั้ง codebase ด้วยเครื่องมือ และรีวิวโค้ดทั้งโปรเจคตาม checklist
- `diff`: รีวิวเฉพาะส่วนที่เปลี่ยน แต่ยังรัน gitleaks และ trivy ทั้งโปรเจค
- `quick`: รันเฉพาะเครื่องมืออัตโนมัติ ตรวจยืนยันเฉพาะ CRITICAL/HIGH แล้วสรุป
- `setup`: ติดตั้งเครื่องมือทั้งหมด (รวม mobsfscan) แล้วจบ

## กฎเหล็ก
- ห้ามแก้โค้ดของโปรเจคจนกว่าผู้ใช้จะสั่ง เขียนไฟล์ได้เฉพาะในโฟลเดอร์ `.security/` และ `.git/info/exclude` เท่านั้น
- ห้ามยิง request ทดสอบใส่ URL หรือเซิร์ฟเวอร์จริง (production) การทดสอบ dynamic ทำได้เฉพาะ localhost และต้องถามก่อน
- ห้ามแสดงค่า secret เต็ม ๆ ในแชทหรือรายงาน ให้ mask เหลือ 4 ตัวท้าย
- ใช้ `--metrics=off` กับ semgrep และห้ามอัปโหลดโค้ดไปบริการภายนอก
- ห้าม `cat` ไฟล์ผล JSON ทั้งก้อน ให้สรุปด้วย `jq` ก่อน
- env var และ `cd` ไม่คงอยู่ข้ามการเรียก Bash แต่ละครั้ง ทุกคำสั่งต้องสมบูรณ์ในตัวเอง และรันจาก root ของโปรเจค
- ถ้าเรียกเครื่องมือแล้วขึ้น `command not found` ให้ลองเรียกผ่าน `~/.local/bin/<tool>`
- เครื่องมือสแกนหลายตัว exit code ไม่เป็น 0 เมื่อเจอ finding ให้ดูว่าไฟล์ผลถูกสร้างหรือไม่ ไม่ใช่ดูแค่ exit code
- เขียนรายงานเป็นภาษาไทย ใช้ศัพท์เทคนิคภาษาอังกฤษได้

---

## Phase 1 — Detect: โปรเจคนี้คืออะไร

ถ้ามี `.security/PROFILE.md` อยู่แล้ว ให้อ่านก่อน แล้วตรวจซ้ำแบบเร็วว่ามีอะไรเปลี่ยน (dependency หรือ platform ใหม่) และอัปเดตถ้าจำเป็น

ใช้ Glob/Grep หา signal ต่อไปนี้ (โปรเจคหนึ่งอาจเข้าหลายหมวด):

| หมวด | Signal |
|---|---|
| **Web – Node** | `package.json` มี next, react, vue, svelte, vite, express, fastify, nestjs, hono |
| **Web – Python** | `requirements.txt` หรือ `pyproject.toml` มี django, flask, fastapi |
| **Web – อื่น ๆ** | `composer.json`, `go.mod`, `Gemfile`, `*.csproj` ที่ใช้ AspNetCore, ไฟล์ `.html` เดี่ยวที่มี `<script>` (single-file app) |
| **Game – Unity** | `ProjectSettings/ProjectVersion.txt`, `Assets/**/*.cs`, `Packages/manifest.json` |
| **Game – Multiplayer** | manifest หรือ code มี Netcode for GameObjects, Mirror, Photon, FishNet, Nakama, PlayFab, `[ServerRpc]`, `[Command]` |
| **Game – อื่น ๆ** | `project.godot`, `export_presets.cfg`, `*.uproject` |
| **Mobile – Android** | `AndroidManifest.xml`, `build.gradle` หรือ `build.gradle.kts` |
| **Mobile – iOS** | `*.xcodeproj`, `Info.plist`, `Podfile` |
| **Mobile – Cross-platform** | `pubspec.yaml` (Flutter), `react-native` หรือ `expo` ใน package.json, `capacitor.config.*`, Unity ที่มี `Assets/Plugins/Android` หรือ `Assets/Plugins/iOS` |
| **Backend-as-a-Service** | `google-services.json`, `GoogleService-Info.plist`, `firebase.json`, `firestore.rules`, `supabase/` |
| **Payment / Subscription** | stripe, omise, paypal, revenuecat, IAP, receipt validation |
| **Infra / Self-host** | `Dockerfile`, `docker-compose*.yml`, `nginx*.conf`, `Caddyfile`, `.github/workflows/`, `*.service`, `.env*` |

เขียนไฟล์ `.security/PROFILE.md`:
```
# Security Profile
- Project type: <web / game / mobile / ผสม>
- Stack: <ภาษา, framework, engine, version>
- Platforms: <browser / Android / iOS / PC / server>
- Online features: <auth, payment, multiplayer, API, BaaS>
- Deployment: <Docker / self-host / cloud / store>
- Sensitive assets: <user data, payment, game currency, API keys>
- Checklists: <A, B, C, D, E>
- Last scanned: <YYYY-MM-DD>
```

ถ้าเป็น git repo ให้กัน `.security/` ไม่ให้ถูก commit โดยไม่แตะ `.gitignore` ของโปรเจค: เพิ่มบรรทัด `.security/` ลงใน `.git/info/exclude` ถ้ายังไม่มี

แสดง profile ให้ผู้ใช้เห็น 3–5 บรรทัด ถ้ามีจุดที่เดาไม่ได้ (เช่น เกมนี้เป็น multiplayer ไหม หรือ build ลงมือถือไหม) ให้ถามแค่ 1 คำถาม ถ้าไม่ได้คำตอบ ให้ถือว่า "ใช่" แล้วตรวจไปด้วย เพราะตรวจเกินดีกว่าตรวจขาด

---

## Phase 2 — Preflight (เช็คเครื่องมือที่ต้องใช้)

เครื่องมือที่ต้องมี: `git semgrep gitleaks trivy jq` และ `mobsfscan` เฉพาะเมื่อ profile มี mobile (หรือโหมด `setup`)

```bash
for t in git semgrep gitleaks trivy jq mobsfscan; do if command -v "$t" >/dev/null 2>&1; then echo "$t OK"; elif [ -x "$HOME/.local/bin/$t" ]; then echo "$t OK (~/.local/bin)"; else echo "$t MISSING"; fi; done; trivy --version 2>/dev/null | head -1
```

**เช็ค Trivy เวอร์ชันอันตราย:** ถ้าได้เวอร์ชัน `0.69.4`, `0.69.5` หรือ `0.69.6` ให้ **หยุดทันที** เพราะเป็น build ที่โดน supply-chain attack (CVE-2026-33634) แจ้งผู้ใช้ให้ลบ trivy ตัวนั้น แล้ว rotate credential ทั้งหมดที่อยู่บนเครื่องนั้น (SSH key, cloud key, token) ก่อนติดตั้งเวอร์ชันใหม่

ถ้ามีเครื่องมือที่ขาด ให้แจ้งรายการ แล้ว **ถามผู้ใช้ก่อนติดตั้ง** โดยใช้คำสั่งตาม OS:

**macOS**
```bash
brew install semgrep gitleaks trivy jq uv
```
ถ้าต้องใช้กับ mobile ให้รันเพิ่ม: `uv tool install mobsfscan`

**Linux / Raspberry Pi** (ไม่ต้องใช้ sudo / ต้องเป็น OS 64-bit)
```bash
set -e; mkdir -p "$HOME/.local/bin"; export PATH="$HOME/.local/bin:$PATH"
case "$(uname -m)" in x86_64) GL=x64; JQ=amd64 ;; aarch64|arm64) GL=arm64; JQ=arm64 ;; *) echo "ต้องใช้ OS 64-bit (x86_64 หรือ arm64)"; exit 1 ;; esac
command -v uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh
uv tool install semgrep
curl -sSL -o "$HOME/.local/bin/jq" "https://github.com/jqlang/jq/releases/latest/download/jq-linux-$JQ" && chmod +x "$HOME/.local/bin/jq"
GLV=$(curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest | grep -oP '"tag_name": "v\K[^"]+')
curl -sSL "https://github.com/gitleaks/gitleaks/releases/download/v${GLV}/gitleaks_${GLV}_linux_${GL}.tar.gz" | tar -xz -C "$HOME/.local/bin" gitleaks
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b "$HOME/.local/bin"
"$HOME/.local/bin/trivy" --version | head -1
```
ถ้าต้องใช้กับ mobile ให้รันเพิ่ม: `uv tool install mobsfscan`

หลังติดตั้งเสร็จ ให้เช็คเวอร์ชัน Trivy ซ้ำตามกฎด้านบน ถ้า `~/.local/bin` ยังไม่อยู่ใน PATH ให้บอกผู้ใช้เพิ่มบรรทัดนี้ใน `~/.bashrc` หรือ `~/.zshrc`:
`export PATH="$HOME/.local/bin:$PATH"`

**Windows:** ให้ใช้ WSL แล้วใช้คำสั่ง Linux ด้านบน

ถ้า semgrep ติดตั้งไม่ได้ ให้ใช้ docker แทน (ถามก่อน):
`docker run --rm -v "$PWD:/src" -w /src semgrep/semgrep semgrep scan --metrics=off --config p/default --json -o .security/raw/semgrep.json`

ถ้าผู้ใช้ไม่ยอมติดตั้ง ให้ทำต่อด้วยเครื่องมือที่มี และระบุในรายงานว่าส่วนไหน "ไม่ได้สแกน"

**ตัวเสริม:** ถ้ามี skill หรือ plugin ของ Trail of Bits (`insecure-defaults`, `supply-chain-risk-auditor`, `sharp-edges`, `differential-review`, `firebase-apk-scanner`) ให้เรียกใช้เสริมใน Phase 4 ถ้าไม่มี ให้แนะนำ 1 บรรทัดท้ายรายงาน: `/plugin marketplace add trailofbits/skills`

---

## Phase 3 — Automated scans

รันทีละคำสั่ง จาก root ของโปรเจค ใส่ `mkdir -p .security/raw` ไว้ต้นคำสั่งแรก

**1. Secrets (รวม git history) — gitleaks**
```bash
mkdir -p .security/raw && if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then gitleaks git . --redact --exit-code 0 --report-format json --report-path .security/raw/gitleaks.json || gitleaks detect --source . --redact --exit-code 0 --report-format json --report-path .security/raw/gitleaks.json; else gitleaks dir . --redact --exit-code 0 --report-format json --report-path .security/raw/gitleaks.json; fi
```
secret ที่อยู่ใน history ถึงจะลบออกจากไฟล์แล้ว ก็ยังนับว่ารั่ว ต้องแนะนำให้ rotate key และไม่ต้องรายงาน `google-services.json` หรือ Supabase anon key ว่าเป็น secret รั่ว เพราะออกแบบมาให้อยู่ฝั่ง client (ให้ไปตรวจใน checklist D แทน)

**2. SAST — semgrep** เลือก config ตาม profile
- ทุกโปรเจค: `--config p/default --config p/secrets`
- Web: เพิ่ม `--config p/owasp-top-ten`
- Unity / C#: เพิ่ม `--config p/csharp`
- Android: เพิ่ม `--config p/kotlin --config p/java`
- iOS: เพิ่ม `--config p/swift`
- มี Dockerfile: เพิ่ม `--config p/dockerfile`
- มี GitHub Actions: เพิ่ม `--config p/github-actions`
```bash
semgrep scan --metrics=off --config p/default --config p/secrets <config เพิ่มเติม> --exclude node_modules --exclude Library --exclude Temp --exclude Build --exclude build --exclude dist --exclude .next --exclude Pods --exclude .security --json -o .security/raw/semgrep.json .
```

**3. Dependencies + misconfig — trivy** (รอบแรกจะดาวน์โหลดฐานข้อมูลช่องโหว่)
```bash
trivy fs --scanners vuln,misconfig,secret --skip-dirs node_modules,Library,Temp,Build,Pods,.security --format json -o .security/raw/trivy.json .
```
ถ้าโปรเจคไม่มี lockfile (เช่น `package-lock.json`, `pnpm-lock.yaml`, `poetry.lock`) trivy จะเช็ค dependency ไม่ได้ ให้ระบุในรายงาน

**4. Mobile source — mobsfscan** (เฉพาะโปรเจค mobile)
```bash
mobsfscan --json -o .security/raw/mobsfscan.json .
```
ถ้าผู้ใช้มีไฟล์ APK/IPA และอยากตรวจ binary ให้แนะนำให้ **ผู้ใช้รันเอง** (คำสั่งนี้ต้องใช้ terminal แบบ interactive):
`docker run -it --rm -p 8000:8000 opensecurity/mobile-security-framework-mobsf:latest` แล้วเปิด http://localhost:8000

**5. โหมด diff — หาไฟล์ที่เปลี่ยน**
```bash
BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || (git rev-parse --verify -q main >/dev/null && echo main) || echo master); git diff --stat "$(git merge-base HEAD "$BASE")"; git ls-files --others --exclude-standard
```
ใช้ผลนี้กำหนดขอบเขตของ Phase 4 และกรองผลจาก semgrep ให้เหลือเฉพาะไฟล์ในรายการนี้

**6. สรุปผลดิบ**
```bash
jq 'length' .security/raw/gitleaks.json
jq '[.results[].extra.severity] | group_by(.) | map({(.[0]): length}) | add' .security/raw/semgrep.json
jq '[.Results[]? | (.Vulnerabilities[]?, .Misconfigurations[]?, .Secrets[]?) | .Severity] | group_by(.) | map({(.[0]): length}) | add' .security/raw/trivy.json
jq '[.results // {} | to_entries[] | .value.metadata.severity] | group_by(.) | map({(.[0]): length}) | add' .security/raw/mobsfscan.json
```
จากนั้นดึงรายละเอียดเฉพาะ HIGH/CRITICAL (semgrep ใช้ `ERROR`) ขึ้นมาตรวจก่อน ถ้าเครื่องมือตัวไหนรันไม่ได้ ให้บันทึกไว้ แล้วทำต่อ

---

## Phase 4 — Manual review ตาม checklist

ข้ามทั้ง Phase นี้ในโหมด `quick` ใช้เฉพาะ checklist ที่ตรงกับ profile ในโหมด `diff` ให้โฟกัสไฟล์ที่เปลี่ยน แต่ตามไปดูโค้ดที่เรียกหรือถูกเรียกด้วย

### A. Web app
- **AuthN**: hash รหัสผ่านด้วย bcrypt หรือ argon2 / มี rate limit ที่ login, OTP และ reset password / reset token ใช้ได้ครั้งเดียวและมีวันหมดอายุ
- **Session / JWT**: cookie ต้องมี `HttpOnly`, `Secure`, `SameSite` / JWT ต้องเช็ค signature, alg และ exp / logout ต้อง invalidate session จริง
- **AuthZ / IDOR**: ทุก endpoint ที่รับ id ต้องเช็คว่าเป็นเจ้าของข้อมูล / route admin ต้องเช็ค role ที่ server ไม่ใช่แค่ซ่อนปุ่ม / ระวัง mass assignment (รับ body ทั้งก้อนแล้วเขียนลง DB ทำให้ user ตั้ง `role` หรือ `isPaid` เองได้)
- **Injection**: SQL/NoSQL ที่ต่อ string, command injection (`exec`, `subprocess` ที่ใช้ `shell=True`), template injection, path traversal
- **XSS**: `dangerouslySetInnerHTML`, `innerHTML`, `v-html`, `|safe`, การ render markdown หรือ HTML จาก user
- **CSRF / CORS**: CORS แบบ `*` พร้อม credentials / endpoint ที่เปลี่ยน state ต้องกัน CSRF
- **SSRF / Upload / Redirect**: fetch URL ที่มาจาก user / upload ที่ไม่จำกัดชนิดหรือขนาด หรือเก็บไว้ใน path ที่ execute ได้ / open redirect ผ่านพารามิเตอร์อย่าง `?next=` หรือ `?url=`
- **Payment / Subscription**: webhook ต้อง verify signature / ราคาและสิทธิ์ต้องคำนวณที่ server / trial ต้องสมัครซ้ำไม่ได้ / สิทธิ์ต้องถูกต้องหลังต่ออายุ ยกเลิก หรือ refund
- **Headers**: CSP, HSTS, `frame-ancestors` หรือ X-Frame-Options, X-Content-Type-Options
- **Secrets & config**: `.env` ห้ามถูก commit / key ฝั่ง server ห้ามหลุดไปใน bundle ของ client (`NEXT_PUBLIC_`, `VITE_`) / ห้ามเปิด debug mode ใน production
- **Single-file HTML app**: API key ที่ฝังใน JS / ใช้ `innerHTML` กับข้อมูลภายนอก / script จาก CDN ที่ไม่มี SRI (`integrity`) / เก็บ token ใน localStorage
- **Error handling**: stack trace หรือ query ห้ามหลุดไปถึง user

### B. Game (Unity / Godot / Unreal)
- **Save tampering**: ห้ามเก็บเงิน ไอเท็ม หรือ progress สำคัญใน PlayerPrefs หรือ JSON ธรรมดาโดยไม่มี integrity check (HMAC) ถ้าเป็นเกม online ค่าเหล่านี้ต้องอยู่ที่ server
- **Insecure deserialization**: `BinaryFormatter`, `NetDataContractSerializer`, Newtonsoft ที่ตั้ง `TypeNameHandling` ไม่เป็น `None`
- **Server authority (multiplayer)**: client ต้องไม่เป็นผู้ตัดสินผล (damage, position, ผลแพ้ชนะ, รางวัล) / ServerRpc หรือ Command ต้อง validate ค่า, cooldown, ระยะ และสิทธิ์ / ต้องมี rate limit ต่อ RPC
- **Economy / IAP**: ต้อง validate receipt ที่ server ไม่ใช่ใน client / ต้องกัน replay ของ receipt
- **Hardcoded secrets**: API key, server secret, admin endpoint ใน C# script, ScriptableObject หรือ Resources ถือว่ารั่ว เพราะ decompile ได้ง่าย
- **Signing**: ห้าม commit `*.keystore`, `*.jks`, `keystore.properties` หรือ `export_presets.cfg` ที่มีรหัสผ่าน
- **Build**: grep `scriptingBackend` ใน `ProjectSettings/ProjectSettings.asset` ตัว release ควรเป็น IL2CPP / build script ห้ามใช้ `BuildOptions.Development` กับ release / ต้องปิด debug menu และ cheat command ใน release
- **Network**: API ต้องใช้ TLS / ต้อง validate และกรอง chat, ชื่อผู้เล่น และ custom data
- จำไว้ว่า anti-cheat ฝั่ง client เป็นแค่การชะลอ ความปลอดภัยจริงต้องอยู่ที่ server

### C. Mobile (OWASP MASVS v2)
- **STORAGE**: token และรหัสผ่านต้องไม่อยู่ใน SharedPreferences, UserDefaults, SQLite หรือไฟล์ธรรมดา ต้องใช้ Keystore หรือ Keychain / log ห้ามมีข้อมูลสำคัญ / ถ้าเก็บข้อมูลสำคัญ ให้ตั้ง `android:allowBackup` เป็น false
- **CRYPTO**: ห้าม hardcode key, ใช้ ECB, ใช้ MD5/SHA1 เพื่อความปลอดภัย, ใช้ IV คงที่ หรือใช้ `Random` แทน SecureRandom
- **AUTH**: biometric ต้องผูกกับ crypto object (CryptoObject / Keychain access control) ไม่ใช่แค่ค่า boolean / session ต้องหมดอายุ
- **NETWORK**: Android ห้ามมี `android:usesCleartextTraffic="true"` หรือ `cleartextTrafficPermitted="true"` และห้ามใช้ TrustManager หรือ HostnameVerifier ที่ยอมรับทุกอย่าง / iOS ห้ามมี `NSAllowsArbitraryLoads` / แอปที่เสี่ยงสูงควรทำ certificate pinning
- **PLATFORM**: component ที่ `exported="true"` ต้องมี permission / deeplink ต้อง validate parameter / WebView ที่เปิด JavaScript พร้อม `addJavascriptInterface` หรือ file access
- **CODE**: ห้าม `debuggable=true` / minSdk ต้องไม่ต่ำเกินไป / dependency เก่า (ดูผล trivy) / signing key ห้ามอยู่ใน repo
- **RESILIENCE**: เปิด R8/ProGuard / root หรือ jailbreak detection เฉพาะแอปเสี่ยงสูง เช่น การเงิน
- **PRIVACY**: ขอ permission เท่าที่จำเป็น / ข้อมูลที่เก็บต้องตรงกับนโยบายความเป็นส่วนตัว
- **Flutter / React Native**: secret ห้ามอยู่ใน `.env` ที่ bundle ไปกับแอป หรืออยู่ใน JS bundle

### D. Backend-as-a-Service (Firebase / Supabase)
- `firestore.rules`, `database.rules.json`, `storage.rules`: ห้ามมี `allow read, write: if true` และห้ามใช้ `request.auth != null` อย่างเดียวโดยไม่เช็คเจ้าของข้อมูล
- Supabase: ทุก table ต้องเปิด RLS / `service_role` key ห้ามอยู่ฝั่ง client
- Firebase API key ต้องตั้ง restriction (app หรือ HTTP referrer) / Cloud Functions ต้องเช็ค auth

### E. Infra / Self-host / CI
- **Dockerfile**: ห้ามรันเป็น root / ห้ามใช้ tag `latest` / ห้าม `COPY` secret เข้า image / ควรใช้ multi-stage
- **docker-compose**: ห้าม bind port ของ DB หรือ Redis ที่ `0.0.0.0` โดยไม่จำเป็น / ห้ามใช้รหัสผ่าน default
- **Reverse proxy**: บังคับ TLS และ redirect HTTP→HTTPS / ปิด directory listing / มี rate limit
- **GitHub Actions**: ห้ามใช้ `pull_request_target` ร่วมกับการ checkout โค้ดของ PR / secret ห้ามหลุดใน log / ทุก action ต้อง pin ด้วย commit SHA / ตั้ง `permissions` เท่าที่จำเป็น
- ถ้า workflow ใช้ `aquasecurity/trivy-action` หรือ `setup-trivy` แบบอ้างด้วย tag ให้รายงานเป็น HIGH และแนะนำให้ตรวจ log ของรันในช่วง 19–22 มี.ค. 2026 กับ rotate secret ของ repo นั้น
- `.env.example` ต้องไม่มีค่าจริง
- สิ่งที่อยู่นอก repo (SSH, firewall, port-forward ของ router, OS update) ตรวจไม่ได้ ให้ระบุในส่วน "ไม่ได้ตรวจ"

**ถ้ามี Trail of Bits plugins:** รัน `insecure-defaults` และ `sharp-edges` กับโค้ดส่วน auth และ config / รัน `supply-chain-risk-auditor` กับ dependency / ใช้ `differential-review` ในโหมด diff / ใช้ `firebase-apk-scanner` ถ้ามี APK

---

## Phase 5 — Verify (ตัด false positive)

กับทุก finding ระดับ MEDIUM ขึ้นไป (โหมด `quick` ทำเฉพาะ CRITICAL/HIGH):
1. เปิดโค้ดจริงที่ตำแหน่งนั้น และอ่านบริบทรอบ ๆ
2. ไล่ดูว่า input จากผู้ใช้ไปถึงจุดนั้นได้จริงไหม (reachable) และมี sanitization หรือ middleware กันไว้แล้วหรือยัง
3. ให้ระดับความมั่นใจ: **Confirmed** / **Likely** / **Needs manual check**
4. ตัด false positive ที่ชัดเจนออก แต่นับจำนวนไว้ในรายงาน
5. finding ที่อยู่ใน test, fixture หรือ example ให้ลด severity ลง เว้นแต่เป็น secret จริง

---

## Phase 6 — Report

เขียนไฟล์ `.security/report-YYYY-MM-DD.md` (ใช้ `date +%F`):

```
# Security Report — <project> — <date>
Profile: <1 บรรทัด> | Mode: <full/diff/quick> | Tools: <ที่รันได้ / ที่ข้าม>

## สรุป
CRITICAL x | HIGH x | MEDIUM x | LOW x | ตัด false positive x
ต้องแก้ก่อน deploy: <1–3 ข้อ>

## Findings
### [SEVERITY] ชื่อปัญหา — Confidence
- ไฟล์: path:line
- ปัญหา: <โจมตีได้อย่างไร อธิบายสั้น ๆ>
- อ้างอิง: <CWE / OWASP / MASVS>
- วิธีแก้: <โค้ดหรือ pattern ที่ต้องเปลี่ยน>

## ไม่ได้ตรวจ / ข้อจำกัด
<เครื่องมือที่ขาด, ส่วนที่ต้องทดสอบ dynamic, ส่วนที่อยู่นอก repo, ส่วนที่ต้องให้คนตรวจ>
```

**เกณฑ์ severity**
- **CRITICAL**: RCE, secret ของ production รั่ว, auth bypass, เข้าถึงข้อมูลผู้ใช้คนอื่นได้, ใช้ของที่ต้องจ่ายเงินได้ฟรี
- **HIGH**: IDOR, SQLi หรือ XSS ที่ exploit ได้, rules ของ Firebase/Supabase เปิดกว้าง, เกม multiplayer ที่ client เป็นผู้ตัดสินผล, CI ที่ใช้ action แบบอ้างด้วย tag ซึ่งเคยถูก compromise
- **MEDIUM**: header ขาด, config ไม่ปลอดภัยที่ต้องมีเงื่อนไขอื่นร่วมถึงจะโจมตีได้, dependency ที่มี CVE แต่ยังไม่ยืนยันว่า reachable
- **LOW**: hardening และ best practice

**ข้อความตอบผู้ใช้ในแชท** ให้สั้น: ประเภทโปรเจคที่ตรวจพบ, จำนวน finding แยกตาม severity, 3 อันดับที่ต้องแก้ก่อน และ path ของรายงาน
จากนั้นถาม 1 คำถาม: "ให้แก้ข้อไหนก่อน?" และห้ามแก้เองจนกว่าผู้ใช้จะตอบ
