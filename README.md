# Wazak

macOS용 소형 플로팅 컴패니언 MVP.

## 실행

### 개발 중 (자동 재시작 권장)

```sh
./dev.sh
```

`Sources/` 하위 `.swift` 파일이 저장될 때마다 자동으로 재빌드하고 앱을 재실행합니다.  
`Ctrl-C`로 종료하면 실행 중인 Wazak도 함께 정리됩니다.

더 빠른 감시를 원하면 `brew install watchexec` 후 동일하게 `./dev.sh`를 실행하면 자동으로 활용됩니다.

### 수동 실행

```sh
set -a; source .env; set +a
swift run Wazak
```

Wazak이 이미 실행 중이라면, 메뉴 바의 `와` 항목에서 먼저 종료한 뒤 다시 실행하세요.

---

`.env` 파일에 다음 내용이 있어야 합니다:

```txt
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

Supabase 설정 없이 로컬 전용으로도 사용할 수 있습니다.

## MVP 동작

- 화면에 말랑이 캐릭터 하나와 그 아래 뱃지가 표시됩니다.
- 마우스를 올리면 좌우 화살표가 나타납니다.
- 화살표로 이전/다음 말랑이로 전환합니다.
- 말랑이를 클릭하면 소리가 재생됩니다.
- 등록된 말랑이는 로컬에 저장되며, Supabase가 설정된 경우 자동으로 동기화됩니다.
- 이미지와 소리는 Supabase Storage의 `malangi-assets` 버킷에 업로드됩니다.

## 임시 에셋 교체

현재 빌드는 코드로 샘플 말랑이를 그리고 짧은 톤을 생성합니다.
실제 에셋을 연결하려면 이미지나 소리 파일을 아래 경로에 추가하세요:

```txt
Sources/Wazak/Resources/
```

그런 다음 `Sources/Wazak/main.swift`에서 `imageName` 또는 `soundName`을 설정하세요.
