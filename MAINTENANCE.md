# Mini IP Manager — 유지보수 문서

이 문서는 이 앱을 이어서 고치는 사람이나 AI가 처음 읽을 문서입니다. 사용법은 [README.md](README.md)에 있습니다.

## 1. 무엇을 하는 앱인가

Windows PC의 네트워크 어댑터 하나를 버튼 한 번으로 두 상태 사이에서 바꿉니다.

- **고정 IP**: 저장해 둔 프로필의 IP·서브넷 마스크·기본 게이트웨이·기본 설정 DNS·보조 DNS를 적용 (제어판 IPv4 속성과 같은 5칸)
- **자동 IP**: IP와 DNS를 모두 DHCP로 받기

예전에 쓰던 `.bat` 두 개(사내용 고정 IP, 외부용 DHCP)를 대체하는 것이 출발점입니다.

### 사용자가 정한 요구사항 (바꾸기 전에 확인할 것)

| 요구사항 | 결정 |
|---|---|
| 앱 이름 | **Mini IP Manager** |
| 고정 IP | 여러 개 저장, 그중 하나를 **기본값**으로 지정, 기본값을 버튼 하나로 적용 |
| 관리 항목 | IP, 마스크, 게이트웨이, **DNS 2개** 모두 |
| 화면 | **최대한 단순하게**. 상태 + 고정 IP/자동 IP 버튼 + 고정 IP 관리 화면 |
| SSID | **쓰지 않음.** 사용자가 버튼으로 설정을 바꾸고, 그다음 회사/외부 Wi-Fi에 직접 붙음. 예전 앱처럼 Windows 설정만 바꿈 |
| 자동 전환 | 한때 만들었다가 **사용자 요청으로 제거함** (SSID 감지, 게이트웨이 ping 등). 다시 넣지 말 것 |
| 실행 | PowerShell 창 없이, 바탕화면 바로가기 더블클릭 → 앱 창(Edge `--app`) |
| 공유 | 친구에게 줄 때는 **고정 IP가 빈 상태**로 시작하고, 처음 실행 때 각자 자기 어댑터와 고정 IP를 등록 |
| 언어 | 화면과 문서는 한국어 |

## 2. 구조

```
브라우저(Edge --app 창)  ──HTTP──>  MiniIpManager.ps1 (localhost:8765, 관리자 권한)
   index.html                         ├─ config.json 읽기/쓰기
                                      └─ netsh로 IP/DNS 변경
```

- 웹 브라우저는 Windows 네트워크 설정을 바꿀 수 없으므로, 관리자 권한으로 도는 로컬 서버가 반드시 필요합니다. "GitHub에서 바로 실행" 같은 순수 웹앱은 불가능합니다.
- 외부 의존성 없음: Windows PowerShell 5.1 + .NET `HttpListener` + `netsh` + Edge만 씁니다.

### 파일

| 파일 | 역할 |
|---|---|
| `MiniIpManager.ps1` | 진입점. 관리자 권한 재실행(UAC), HTTP 서버, 설정 저장, netsh 실행 |
| `index.html` | 화면 전체(HTML/CSS/JS 한 파일). 해시 라우팅 `#/`(전환), `#/manage`(고정 IP 관리) |
| `설치.cmd` | 친구용 설치. 파일 차단 해제(`Unblock-File`), 실행 정책 확인, `install.ps1` 실행 |
| `install.ps1` | 바탕화면 바로가기 `Mini IP Manager.lnk` 생성 |
| `config.json` | PC별 설정. **git에 올리지 않음**(.gitignore) |
| `mini-ip-manager.log` | 변경 기록. git에 올리지 않음 |

### 실행 흐름

1. 바로가기: `powershell.exe -NoProfile -WindowStyle Hidden -File "<폴더>\MiniIpManager.ps1"` (창 최소화)
2. 관리자가 아니면 `Start-Process -Verb RunAs`로 자기 자신을 숨김 창으로 다시 실행하고 종료
3. `HttpListener`를 `http://localhost:8765/`에 열고 Edge `--app` 창을 띄움
4. 포트가 이미 열려 있으면(이미 실행 중) 앱 창만 다시 열고 종료
5. 화면의 **끄기** → `/api/shutdown` → 서버 루프 종료

스크립트 매개변수: `-Port <n>`(기본 8765), `-NoElevate`(관리자 재실행 안 함, 시험용), `-NoBrowser`(창 안 띄움).

## 3. API

모든 응답은 JSON. POST는 헤더 `X-MiniIp: 1`이 있어야 하고, `Origin`이 있으면 `http://localhost:<port>` 또는 `http://127.0.0.1:<port>`여야 합니다(다른 사이트의 CSRF 차단). 아니면 403.

| 메서드 | 경로 | 설명 |
|---|---|---|
| GET | `/` | `index.html` |
| GET | `/api/status` | `{ isAdmin, adapters[], config }` |
| POST | `/api/config` | 설정 전체를 받아 검증 후 저장. 응답은 status와 같음 |
| POST | `/api/apply` | `{ mode: "static", profileId }` 또는 `{ mode: "dhcp" }`. 응답은 status |
| POST | `/api/shutdown` | 서버 종료 |

오류는 400 + `{ error: "한국어 메시지" }`. 화면은 이 메시지를 그대로 토스트로 보여 줍니다.

### adapters[] 항목

`index, name, description, status, dhcp, ip, mask, gateway, dns[], ssid, mode, profileId, profileName`
`mode`는 `dhcp` / `static`(등록된 프로필과 IP 일치) / `static-other`(등록 안 된 고정 IP). `ssid`는 표시용일 뿐 로직에 쓰지 않습니다.

### config.json

```json
{
  "adapterIndex": 18,
  "defaultProfileId": "5a0079d3",
  "profiles": [
    { "id": "5a0079d3", "name": "본사", "ip": "192.168.0.100", "mask": "255.255.255.0",
      "gateway": "192.168.0.1", "dns1": "8.8.8.8", "dns2": "8.8.4.4" }
  ]
}
```

- `adapterIndex`는 Windows `ifIndex`. PC마다 다르므로 config를 다른 PC로 복사하면 안 됩니다.
- 서버의 `ConvertTo-Config`가 검증합니다: IP/마스크 필수, 마스크는 연속 비트, 게이트웨이/DNS는 선택, 보조 DNS만 있는 것은 거부, 기본값이 없으면 첫 프로필.
- 화면(`readForm`)에서도 같은 형식 검사와 **IP 중복 검사**를 합니다.

## 4. IP 변경 명령 (netsh)

`ifIndex`(`name=<숫자>`)로 지정해 어댑터 이름의 한글·공백 문제를 피합니다.

```
# 고정
netsh interface ipv4 set address name=<idx> source=static address=<ip> mask=<mask> gateway=<gw> gwmetric=1
netsh interface ipv4 set dnsservers name=<idx> source=static address=<dns1> register=primary validate=no
netsh interface ipv4 add dnsservers name=<idx> address=<dns2> index=2 validate=no
# 자동
netsh interface ipv4 set address name=<idx> source=dhcp
netsh interface ipv4 set dnsservers name=<idx> source=dhcp
ipconfig /renew "<어댑터 이름>"
```

## 5. 처음 실행(친구용) 흐름

`index.html`의 `firstRun()`:
- 프로필이 하나도 없으면 `#/manage`로 이동, 환영 안내(`#welcome`) 표시
- 어댑터가 미선택이고 "연결됨 + 게이트웨이 있음"인 어댑터가 하나뿐이면 자동 선택·저장
- 등록 폼을 열고 **기본값으로 사용**을 미리 체크
- **현재 설정 가져오기**: 지금 어댑터 값으로 폼을 채움(DHCP 상태면 경고)

## 6. 함정 (실제로 겪은 것)

| 문제 | 원인 / 해결 |
|---|---|
| PS 5.1에서 한글이 깨짐 | `.ps1`은 **UTF-8 BOM**으로 저장해야 함. BOM 없으면 ANSI(CP949)로 읽음 |
| `/api/status`가 "인수 형식이 일치하지 않습니다" | PS 5.1에서 빈 `List[object]`를 `@()`로 감싸 `[ordered]@{}`에 넣으면 오류. `.ToArray()` 사용 |
| 백그라운드 실행 시 SSID가 비어 있음 | `netsh wlan show interfaces`의 항목 이름(Name/이름)이 인코딩마다 다름 → 값이 어댑터 이름과 같은 줄로 인터페이스를 찾음 |
| `설치.cmd`가 줄마다 "명령이 아닙니다" | cmd는 콘솔 코드 페이지로 배치 파일을 읽음. UTF-8/CP949 한글 모두 깨짐 → **cmd는 ASCII만**, 한글 메시지는 `install.ps1`로 |
| 받은 zip의 스크립트가 실행 안 됨 | 인터넷 영역 표시(Zone.Identifier) + RemoteSigned. `설치.cmd`가 `Unblock-File` 처리 |
| `-ExecutionPolicy Bypass` 사용 | 쓰지 않기로 함(보안 검사에서 막혔고, 친구 PC에서 정책을 우회하지 않기 위해). RemoteSigned + 차단 해제로 해결 |
| PS 5.1 `Compress-Archive` zip | 경로 구분자가 `\`라 일부 도구에서 깨짐. 배포 zip은 `git archive`나 .NET `ZipArchive`로 `/` 경로 사용 |
| 첫 상태 조회가 몇 초 걸림 | `Get-NetAdapter`/`netsh` 조회가 느림. 화면은 "불러오는 중…" 표시 후 자동 갱신(5초마다) |
| 작업 폴더가 통째로 사라짐 | 처음엔 SAP Harness 작업 폴더에 두었는데 앱 업데이트 때 초기화됨. 지금은 `%USERPROFILE%\mini-ip-manager`에 둠 |

## 7. 시험하는 법

관리자 권한 없이(IP 변경 없이) 서버만 띄워 확인:

```
powershell -NoProfile -File .\MiniIpManager.ps1 -Port 8799 -NoElevate -NoBrowser
```

- `GET http://localhost:8799/api/status` → 어댑터 목록
- 헤더 없는 POST → 403, 다른 Origin → 403
- 비관리자에서 `/api/apply` → "관리자 권한이 아니어서..." 400
- 잘못된 IP로 `/api/config` → 400
- 실제 IP 변경은 관리자 권한 + **회사 내부망**에서만 시험(밖에서 고정 IP를 걸면 인터넷이 끊김 — 정상)

시험 전에 `config.json`을 백업하고 끝나면 되돌리세요.

## 8. 배포 (GitHub)

- 저장소: `https://github.com/hunykang/mini-ip-manager` (공개)
- 친구용 다운로드: 릴리스 첨부파일 `Mini-IP-Manager.zip`
  고정 링크 `https://github.com/hunykang/mini-ip-manager/releases/latest/download/Mini-IP-Manager.zip`
- zip 안 구조: `Mini IP Manager/` 폴더 아래 `MiniIpManager.ps1, index.html, README.md, MAINTENANCE.md, 설치.cmd, install.ps1` (**config.json 없음**)
- 새 버전 내기:

```
git archive --format=zip --prefix="Mini IP Manager/" -o Mini-IP-Manager.zip HEAD
gh release create v1.x.y Mini-IP-Manager.zip --title "v1.x.y" --notes "변경 내용"
```

`.gitattributes`가 `.cmd`/`.ps1`을 CRLF로 내보내므로 `git archive`로 만든 zip을 그대로 쓰면 됩니다.

## 9. 하지 말 것

- `config.json`, 로그, 실제 사내 IP를 저장소나 zip에 넣지 않기 (공개 저장소)
- SSID 감지·자동 전환 등 사용자가 뺀 기능을 다시 넣지 않기
- `-ExecutionPolicy Bypass`, `irm | iex` 같은 우회 실행 방식을 쓰지 않기
- 화면을 다시 복잡하게 만들지 않기
