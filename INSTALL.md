# ERPNext 도커 설치 가이드 (개발/테스트용: 항상 초기화 후 재설치)

이 프로젝트는 **개발/테스트 환경**을 목적으로 합니다.

아래 설치 스크립트를 실행하면 **기존 Docker 볼륨(DB/사이트 데이터)이 삭제**되고,
항상 **완전히 새로 설치**됩니다.

## 주의 (매우 중요)

- **데이터가 모두 삭제됩니다.**
  - `docker compose down -v`를 수행하므로 DB/사이트 볼륨이 초기화됩니다.
  - 운영/실데이터 환경에서는 사용하지 마세요.

## 준비 사항

- Docker Desktop 설치
- Git 설치

## Windows (PowerShell)

레포 루트( `compose.yaml` 이 있는 폴더)에서 실행:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1
```

옵션 파라미터(사이트명/비밀번호 변경):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1 -SiteName erp.localhost -DbRootPassword admin -AdminPassword admin
```

## Linux/macOS

```bash
chmod +x ./scripts/setup.sh
./scripts/setup.sh
```

옵션 파라미터:

```bash
./scripts/setup.sh erp.localhost admin admin
```

## 접속 정보

- URL
  - http://localhost:8080
- 계정
  - ID: `Administrator`
  - PW: `admin` (또는 스크립트에서 지정한 관리자 비밀번호)

## 스크립트가 자동으로 수행하는 작업

- 컨테이너/볼륨 초기화
  - `docker compose down -v`
- 컨테이너 기동
  - `docker compose up -d`
- `custom_apps` 설치 준비
  - `sites/apps.txt`에 `custom_apps`를 추가
  - backend/worker/scheduler 컨테이너에 `custom_apps`를 editable install
- 사이트 생성 및 ERPNext 설치
  - `bench new-site ... --install-app erpnext --force`
- 커스텀 앱 설치
  - `bench --site <site> install-app custom_apps`
- Item Group 초기화 및 7개 그룹 생성(자동)
  - `All Item Groups` 하위 Item Group을 초기화하고
  - `상품`, `원재료`, `부재료`, `제품`, `반제품`, `부산품`, `저장품` 7개를 생성
