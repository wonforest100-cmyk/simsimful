# 국비 교부신청서 작성기

교부신청서 · 사업 실적 · 정산/실적보고서를 한곳에서 작성하는 웹 프로그램입니다.
GitHub Pages로 열고, 자료는 Supabase에 저장합니다.

**설정 방법은 `guide.html` (그림으로 된 안내서)를 브라우저로 열어 보세요.** 아래는 요약입니다.

| 파일 | 하는 일 |
|---|---|
| `index.html` | 작성기 프로그램 |
| `guide.html` | 화면 그림이 들어간 설정 안내서 |
| `supabase/setup.sql` | Supabase에 표·권한·휴면 방지 함수를 만드는 SQL |
| `.github/workflows/supabase-keepalive.yml` | 2일마다 Supabase에 접속해 휴면을 막는 자동 작업 |
| `keepalive/last-ping.txt` | 자동 작업이 매달 1일 갱신 (GitHub 예약 작업이 60일 뒤 멈추지 않게) |

## 순서 요약
1. Supabase › New project (Region: Northeast Asia (Seoul))
2. SQL Editor에 `supabase/setup.sql` 붙여넣고, 맨 아래 이메일을 관리자 이메일로 바꿔 Run
3. 위쪽 **Connect** 또는 Project Settings › API Keys에서 **Project URL**과 **Publishable key**(`sb_publishable_…`) 복사
4. GitHub에 새 저장소를 만들고 이 폴더의 파일을 전부 올리기 (`.github` 포함)
5. Settings › Pages › Deploy from a branch › `main` / `(root)` › Save
6. Supabase › Authentication › URL Configuration: Site URL과 Redirect URLs(`주소/**`)에 Pages 주소 등록
7. GitHub Settings › Secrets and variables › Actions: `SUPABASE_URL`, `SUPABASE_KEY` 등록
8. Actions › Supabase 휴면 방지 › Run workflow → 초록색 체크 확인
9. 기존 PC 파일에서 백업(JSON) → 새 주소에서 복원
10. 새 주소에서 서버 연결 → 회원가입(관리자 이메일) → 메일 인증 → 로그인

## 알아 둘 것
- Supabase 무료 플랜은 7일 동안 활동이 없으면 일시 중지됩니다. 8단계 작업이 2일마다 깨워 줍니다.
- 누구나 회원가입하고 메일 인증을 마치면 바로 자료를 보고 고칠 수 있습니다. 관리자는 작성기의 회원 관리에서 사용을 막을 수 있습니다.
- Supabase 기본 메일은 시간당 보낼 수 있는 수가 적습니다. 사람이 많으면 Custom SMTP를 연결하세요.
- 예전 anon 키는 Supabase가 2026년 말에 없앨 예정이라 Publishable key를 씁니다. Secret key는 절대 넣지 마세요.
