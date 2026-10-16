# PC 전원 자동 스케줄 가이드

> **방식**: 매일 정해진 시각에 **재부팅 후 최대절전(Hibernate)** 으로 전환하고, 정해진 시각에 **자동으로 깨어나는** 스케줄
>
> **목적**: 며칠씩 켜두면 느려지는 문제를 매일 재부팅으로 해결하면서, 원격 접속이 필요한 시간대에만 전원이 켜지도록 자동화

---

## 1. 동작 방식 (하루 사이클)

```
05:00  ── 깨우기 ──▶  절전 상태에서 자동으로 전원 ON
08:00  ── 절전 ───▶  재부팅 실행 → 부팅 완료 직후 자동으로 최대절전 진입
17:00  ── 깨우기 ──▶  절전 상태에서 자동으로 전원 ON
23:00  ── 절전 ───▶  재부팅 실행 → 부팅 완료 직후 자동으로 최대절전 진입
(다음날 05:00 반복)
```

### "재부팅 후 절전" 이 핵심인 이유

- **재부팅**으로 매번 깨끗한 시스템 상태를 만든다 → 오래 켜두면 누적되는 메모리 누수 / 느려짐 문제 해결
- 최종적으로 **최대절전(Hibernate)** 상태가 되므로 전력 소모가 거의 0에 가깝다
- 최대절전 상태에서도 예약된 시각에 **자동으로 깨어난다** (Windows 작업 스케줄러 + RTC wake timer)

### 동작 상태 전이(전원 기준)

| 시간대 | 상태 | 비고 |
|--------|------|------|
| 05:00 ~ 08:00 | **ON** (사용 가능) | |
| 08:00 ~ 17:00 | **절전(최대절전)** | 전력 거의 0 |
| 17:00 ~ 23:00 | **ON** (사용 가능) | |
| 23:00 ~ 05:00 | **절전(최대절전)** | 전력 거의 0 |

---

## 2. 설치된 파일 목록

모든 파일은 **`C:\PC-Power-Schedule\`** 폴더에 있습니다.

| 파일 | 역할 |
|------|------|
| `config.json` | **시간 설정 파일** (켜는 시각 / 끄는 시각) |
| `Register-Schedule.ps1` | 시간 설정을 읽어 작업 스케줄러에 등록/갱신 + wake timer 활성화 |
| `Sleep-Scheduled.ps1` | 최대절전 플래그 생성 후 재부팅 (`shutdown /r`) |
| `Boot-HibernateCheck.ps1` | 부팅 직후 실행되어 플래그 + 시간대 검사 후 최대절전 진입 (`shutdown /h`) |
| `Wake-Scheduled.ps1` | 깨우기 시각에 실행되어 로그만 기록 |
| `schedule.log` | 모든 동작 기록 (정상 동작/문제 추적용) |

### `config.json` 예시 (현재 설정)

```json
{
  "wakeTimes": ["05:00", "17:00"],
  "sleepTimes": ["08:00", "23:00"],
  "rebootDelaySeconds": 10
}
```

- `wakeTimes` : 자동으로 켜지는 시각들
- `sleepTimes` : 자동으로 재부팅 후 절전되는 시각들
- `rebootDelaySeconds` : 끄기 시각에 재부팅까지의 유예 시간(초)

---

## 3. 등록된 작업(태스크)

작업 스케줄러에 다음 3개의 작업이 등록되어 있습니다. (모두 `SYSTEM` 권한으로 실행)

| 작업 이름 | 실행 시각 | 동작 |
|-----------|-----------|------|
| `PCPower-Wake` | 05:00, 17:00 (매일) | 절전 상태에서 PC를 깨움 (`WakeToRun` 활성화) |
| `PCPower-Sleep` | 08:00, 23:00 (매일) | 플래그 생성 후 재부팅 |
| `PCPower-BootCheck` | 부팅 시 (매번) | 플래그가 있고 꺼짐 시간대면 최대절전 진입 |

### 안전장치

- **플래그 + 시간대 이중 검사**: `BootCheck`는 `Sleep` 태스크가 만든 플래그가 **있고** 현재 시각이 **꺼짐 시간대**일 때만 최대절전에 들어갑니다. 덕분에:
  - 정전 등으로 재부팅이 실패해 플래그가 남아도, 켜짐 시간대에는 절전하지 않고 정상 부팅을 유지합니다.
  - 사용자가 낮에 수동으로 재부팅해도 자동으로 절전되지 않습니다.
- **`StartWhenAvailable`**: 정전 등으로 밀린 작업은 전원이 복구되면 자동으로 따라잡아 스케줄을 다시 맞춥니다.

---

## 4. 시간 변경 방법 (BIOS 접근 불필요)

1. 메모장으로 **`C:\PC-Power-Schedule\config.json`** 을 열어 시각을 수정합니다. (24시간 형식 `"HH:MM"`)
2. **관리자 권한** PowerShell에서 아래 명령을 실행하여 작업을 갱신합니다:

```powershell
powershell -ExecutionPolicy Bypass -File C:\PC-Power-Schedule\Register-Schedule.ps1
```

> ⚠️ `Register-Schedule.ps1`은 반드시 **관리자 권한**으로 실행해야 합니다. (태스크 등록 및 전원 옵션 변경에 필요)

---

## 5. 자동 켜기/끄기 중지 · 재개 방법

### 5-1. 완전히 제거 (자동 켜기/끄기를 아예 안 함) ★ 자주 쓰는 명령

**자동 켜기 / 자동 끄기를 모두 멈추려면 아래 한 줄이면 됩니다.** 3개 작업이 전부 삭제됩니다:

```powershell
Unregister-ScheduledTask -TaskName 'PCPower-Wake','PCPower-Sleep','PCPower-BootCheck' -Confirm:$false
```

- 이후에는 PC가 스스로 켜지거나 꺼지지 않습니다. **원하실 때 직접** 켜고 끄시면 됩니다.
- 프로그램 파일(`config.json`, 스크립트)은 그대로 남아 있습니다.

### 5-2. 다시 켜고 싶을 때 (복원)

```powershell
powershell -ExecutionPolicy Bypass -File C:\PC-Power-Schedule\Register-Schedule.ps1
```

`Register-Schedule.ps1`은 `config.json`을 다시 읽어 작업을 재등록하므로, **삭제 후 복원도 이 명령 하나로** 됩니다.

### 5-3. 일시 중지 (설정은 유지, 잠깐만 멈춤)

삭제하지 않고 잠시 꺼두고 싶을 때:

```powershell
# 일시 중지
Disable-ScheduledTask -TaskName 'PCPower-Wake','PCPower-Sleep','PCPower-BootCheck'

# 다시 재개
Enable-ScheduledTask -TaskName 'PCPower-Wake','PCPower-Sleep','PCPower-BootCheck'
```

### 정리

| 목적 | 명령 | 결과 |
|------|------|------|
| **완전 제거** (자동 켜기/끄기 안 함) | `Unregister-ScheduledTask ...` | 작업 삭제, 완전 중단 |
| **다시 켜기** | `Register-Schedule.ps1` 실행 | 작업 재등록 |
| **일시 중지** | `Disable-ScheduledTask ...` | 비활성화만 (설정 유지) |
| **재개** | `Enable-ScheduledTask ...` | 다시 활성화 |

---

## 6. 수동으로 켜고 끄는 방법

자동 스케줄을 중지한 뒤, 또는 필요할 때 직접 제어하는 방법입니다.

### 켜기 (절전 상태 → ON)

- **물리적 전원 버튼**을 누르면 최대절전에서 깨어납니다.
- (원격에서는 Wake-on-LAN이 설정되어 있어야 켤 수 있습니다. 현재는 미설정.)

### 지금 바로 끄기 (재부팅 없이 바로 최대절전)

- 시작 메뉴 → 전원 → **"최대 절전 모드"** 선택, 또는
- 관리자 PowerShell에서:
```powershell
shutdown /h
```

### 지금 바로 "재부팅 후 절전" 을 수동 실행

스케줄을 기다리지 않고 즉시 재부팅 후 절전하고 싶을 때:
```powershell
powershell -ExecutionPolicy Bypass -File C:\PC-Power-Schedule\Sleep-Scheduled.ps1
```
> 이 명령은 **PC를 즉시 재부팅**합니다. 실행 전 저장 안 된 작업이 없는지 확인하세요. (재부팅 후 `BootCheck`가 자동으로 절전시킵니다.)

---

## 7. 정상 동작 확인 방법

### 현재 등록 상태 / 다음 실행 시각 확인

```powershell
Get-ScheduledTask -TaskName 'PCPower-*' | Get-ScheduledTaskInfo | Select-Object TaskName, NextRunTime, LastTaskResult
```

### 동작 로그 확인 (가장 확실한 방법)

```powershell
Get-Content C:\PC-Power-Schedule\schedule.log -Tail 30
```

정상이라면 이런 기록이 남습니다:
- `Wake task fired...` → 자동으로 켜짐
- `Boot check: conditions met. Hibernating now.` → 재부팅 후 자동 절전됨
- `Scheduled sleep: hibernate flag created...` → 끄기 시각에 재부팅 시작됨

### 대기 중인 예약 깨우기 확인

```powershell
powercfg /waketimers
```

### wake timer 활성 여부 확인

```powershell
powercfg /q SCHEME_CURRENT SUB_SLEEP RTCWAKE
```
출력에서 `현재 AC 전원 설정 색인: 0x00000001` 이면 정상(사용)입니다.

---

## 8. 주의사항

1. **08:00 / 23:00 재부팅은 강제 종료(`/f`)입니다.**
   해당 시각에 저장되지 않은 작업이 있으면 닫힙니다. 원격 작업은 그 전에 반드시 저장하세요.

2. **최대절전은 시스템 상태를 저장합니다.**
   "슬립(대기)"이 아니라 최대절전(S4)이므로 전력 소모는 거의 없지만, 완전 종료와 달리 이전 상태가 복원됩니다. 매번 재부팅을 앞에 두어 누적 문제를 방지합니다.

3. **하드웨어가 절전 상태에서의 RTC 깨우기를 지원해야 합니다.**
   대부분의 최신 PC는 지원하지만, 만약 자동 켜짐이 안 되면 펌웨어(BIOS)의 RTC Alarm 지원 여부를 확인해야 합니다.

4. **배터리 노트북인 경우**
   `wakeTimes` 시각에 배터리로 켜져 있으면 방전될 수 있습니다. 데스크톱/상시 전원 사용을 권장합니다.

---

## 9. 문제 해결 (Troubleshooting)

| 증상 | 확인 / 해결 |
|------|-------------|
| 정해진 시각에 자동으로 안 켜짐 | `schedule.log`에 `Wake task fired`가 있는지 확인. 없으면 → 펌웨어 RTC wake 미지원 가능성. BIOS 설정 또는 Wake-on-LAN 대안 검토 |
| 08:00/23:00에 안 꺼짐 | `schedule.log`에 `hibernate flag created`가 있는지 확인. `powercfg /a`로 최대절전 지원 확인 (`shutdown /h`가 실패하면 로그에 에러 기록) |
| 재부팅 후 절전이 안 됨 | `Boot-HibernateCheck.ps1`의 플래그가 지나치게 오래 남았는지 확인. 로그의 `stale flag discarded` 메시지 참고 |
| 작업이 안 보임 | `Get-ScheduledTask -TaskName 'PCPower-*'` 실행. 없으면 `Register-Schedule.ps1` 재실행 |
| 시간을 바꿨는데 반영 안 됨 | `config.json` 수정 후 **`Register-Schedule.ps1`을 다시 실행**해야 반영됩니다 |

---

## 부록: 전체 명령 요약 (복사용)

```powershell
# ── 등록 상태 보기 ──────────────────────────────
Get-ScheduledTask -TaskName 'PCPower-*' | Get-ScheduledTaskInfo |
    Select-Object TaskName, NextRunTime, LastTaskResult

# ── 로그 보기 ──────────────────────────────────
Get-Content C:\PC-Power-Schedule\schedule.log -Tail 30

# ── 자동 켜기/끄기 완전 제거 ★ ────────────────────
Unregister-ScheduledTask -TaskName 'PCPower-Wake','PCPower-Sleep','PCPower-BootCheck' -Confirm:$false

# ── 다시 켜기(복원) / 시간 변경 반영 ──────────────
powershell -ExecutionPolicy Bypass -File C:\PC-Power-Schedule\Register-Schedule.ps1

# ── 일시 중지 / 재개 ─────────────────────────────
Disable-ScheduledTask -TaskName 'PCPower-Wake','PCPower-Sleep','PCPower-BootCheck'
Enable-ScheduledTask  -TaskName 'PCPower-Wake','PCPower-Sleep','PCPower-BootCheck'

# ── 지금 바로 재부팅 후 절전 ──────────────────────
powershell -ExecutionPolicy Bypass -File C:\PC-Power-Schedule\Sleep-Scheduled.ps1

# ── 지금 바로 최대절전 (재부팅 없이) ──────────────
shutdown /h
```

---

*본 문서는 `C:\PC-Power-Schedule\` 폴더의 스크립트 구성과 함께 사용됩니다. 시간 변경은 `config.json` 수정 후 `Register-Schedule.ps1` 실행으로 완료됩니다.*
