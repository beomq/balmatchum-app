# 사진 편집 기능

## 조립 API

`lib/features/photo/photo_screen.dart`의 `PhotoScreen`은 라우터를 소유하지 않는다.
선택된 품종의 실제 `spritePath`와 저장된 이름을 전달한다. 화면은 기본 시츄나 새 포즈로
대체하지 않는다. 앱 조립부에서 플랫폼 어댑터를 만들고 같은 화면 수명 동안 유지한다.

```dart
PhotoScreen(
  dogAssetPath: selectedDog.spritePath,
  dogName: savedDogName,
  adapter: PlatformPhotoAdapter(),
  onBack: () => context.pop(),
  onHome: () => context.go('/home'), // 실제 앱의 홈 경로로 연결
)
```

어댑터 import는 `features/photo/platform_photo_adapter.dart`다. 테스트에서는
`PhotoAdapter`를 생성자로 주입한다. 홈과 라우터 변경은 리드가 담당한다.

## 부모 소유 설정

부모가 설치한 패키지는 `image_picker: 1.2.4`, `gal: 2.3.2`, `share_plus: ^13.0.0`
(resolved 13.3.1)이다.
공유 API는 `SharePlus.instance.share(ShareParams(...))`를 사용한다.
`share_plus: 12.0.2`는 solver 충돌로 채택하지 않았다. 부모는 기존 `geolocator`,
SDK constraints 및 다른 작업자의 `world_holidays`를 유지하고 override 없이 해결했다.
이 기능 작업자는 pubspec/lock/권한 파일을 수정하지 않는다.

iOS Info.plist 요청:

- `NSCameraUsageDescription`: 사진에 반려견을 함께 담기 위해 카메라를 사용합니다.
- `NSPhotoLibraryUsageDescription`: 반려견과 함께 편집할 사진을 선택합니다.
- `NSPhotoLibraryAddUsageDescription`: 반려견과 합성한 사진을 사진 보관함에 저장합니다.

Android 요청:

```xml
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="29" />
```

시스템 사진 선택기는 읽기 권한을 추가하지 않는다. 저장은 특정 앨범을 만들지 않으므로
Android legacy storage 설정을 요구하지 않는다. 카메라만 사용하며 마이크 권한은 없다.

## 편집 및 출력

`DogSticker`는 사진 크기에 대한 상대 중심 위치, 배율, 라디안 회전과 좌우 반전을 가진다.
창 크기가 바뀌어도 상대 좌표가 보존된다. 한 손가락 끌기와 두 손가락 크기/회전 외에
슬라이더와 반전/초기화 버튼을 제공한다. 원본 비율 그대로 표시하고 crop하지 않는다.
`paintPhoto`가 미리보기와 PNG 출력을 함께 그리므로 조작 UI는 출력에 포함되지 않는다.
긴 변 4096px로 디코딩/출력을 제한해 메모리 사용을 줄이며 원본 파일은 쓰지 않는다.
저장과 OS 공유에는 합성된 PNG만 전달한다. 네트워크 호출이나 업로드 코드는 없다.

취소·잘못된 이미지·권한 거부 시 이전 사진과 편집을 유지한다. 새 이미지 디코딩이
완료된 경우에만 편집을 초기화한다. 저장 완료는 Gal 호출이 성공한 뒤에만 표시한다.
공유 성공 응답은 수신 앱 선택을 뜻하며 상대방에게 전송 완료했다고 표시하지 않는다.
Android activity 종료의 lost picker 결과는 화면 초기화 시 복구한다. 앱 프로세스 종료
직전의 기존 편집 상태를 디스크에 저장하는 기능은 없으므로 OS 강제 종료 후 편집 복구는
보장하지 않는다. 리드는 startup의 lost-data 호출과 화면 재진입 연결을 확인해야 한다.

## 디자인 근거와 직접 확인

권위 있는 app-v2 Pen 파일에는 `SET-04` 사진 권한과 사진 바로가기가 있고 별도 사진
편집 프레임은 없다. `SET-04`의 실제 목적/제한 계약, 기존 `meetingTheme`의 폰트·표면·
버튼, 승인된 품종 PNG를 사용한다. 모바일 한 열, 840 이상 두 열이며 전체 콘텐츠가
스크롤한다. 부모 디자인 파일을 새로 만들거나 수정하지 않았다.

```sh
fvm flutter test --no-pub test/features/photo
fvm dart analyze lib/features/photo test/features/photo
fvm flutter test --no-pub --dart-define=PHOTO_RENDER=true test/features/photo/photo_screen_test.dart
```

출력 캡처는 `test/features/photo/render-390.png`, `render-1024.png`, `render-320.png`다.
실제 Pretendard를 로드한 Flutter 위젯 렌더이며 실기기 사진 라이브러리 화면이 아니다.
모델 테스트는 원본 바이트 불변, PNG 출력, 변환 효과, 취소·오류·저장 권한 실패 후 편집
보존을 확인한다. 어댑터 fake는 실제 결과/오류/취소를 반환하며 OS 작업 성공을 증명하지
않는다. 실기기 통합 QA는 리드가 수행한다: 갤러리 PNG/JPEG/HEIC와 카메라 사진 선택,
다섯 변환 후 저장한 PNG 비교, 사진 앱에서 실제 저장 확인, OS 공유 대상 수신 확인,
권한 거부 후 설정에서 허용/재시도, 저장 공간 부족, iPad 공유 popover 위치 확인.

2026-10-14 실행 결과: 포맷 6파일 변경 없음, `fvm dart analyze lib/features/photo
test/features/photo` No issues found, 사진 테스트 8개 통과(모두 종료 코드 0).
390×844, 1024×768, 320×568 캡처를 직접 열어 확인했다. 위치 이동, 승인된 퍼그
자산의 비율, 폰트, 넓은 폭 좌우 배치가 표시되며 모바일 저장/공유는 스크롤로 접근한다.
같은 크기에서 2배 글자와 저장 권한 오류 보존도 위젯 테스트로 확인했다.
Gal의 실제 MethodChannel 어댑터 테스트는 허용 시 PNG 바이트 전달, 거부 시 저장 호출
없음을 확인한다. 네이티브 디바이스 빌드 및 OS 갤러리/카메라/공유 QA는 이 세션에서
실행하지 않았다. 전체 앱 테스트/통합 빌드와 라우터 연결은 부모가 담당한다.

장애 확인 순서는 pub solver/등록된 플러그인 → Info.plist/Manifest → OS 권한 → 사진
디코딩 → `PhotoEditor.capturePng` → Gal/공유 응답이다. Context7 도구 검색은 결과가
없어 현재 공식 패키지 소스와 아래 문서를 읽었다. 사용자 이해나 직접 QA 완료는 미확인이다.

- https://pub.dev/packages/image_picker
- https://pub.dev/packages/gal
- https://pub.dev/packages/share_plus
