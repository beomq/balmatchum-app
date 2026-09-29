# Apple match bootstrap 및 hosted 검증 준비

## 게시 완료

- private 저장소: `beomq/balmatchum-signing`, main
- commit: `dc83efcf76896849921f14eab65c22faac5c3017`
- 메시지: `chore: 기존 Apple 배포 인증서와 프로파일 암호화 보관`
- 원격 tracked blob 6개를 GET으로 읽어 match v2 헤더와 로컬 암호문 byte equality를 모두 확인했다. private=true를 게시 후 재확인했다.
- 자산: `certs/distribution/848N8ZSD6A.cer`, `.p12`, `profiles/appstore/AppStore_<bundle>.mobileprovision` 4개. bundle은 `com.beomq.balmatchum`, `.watchkitapp`, `.dev`, `.dev.watchkitapp`이다.
- 원본 비밀번호·p8·평문 p12는 Git에 없다. 기존 identity와 프로파일만 사용했다. 발급·revoke·portal write는 없다. 각 암호문 hash와 로컬 복호화 증거는 `ASC_READONLY_VERIFIED_20260929.md`에 있다.

## deploy key 검증 범위

### 후속 실제 CI 진단

- 후속 자동 실행 `36567264501`도 SHA `afa0f4b421244be710cff2a2e80a75d16ab3f4e6`에서 성공했다. 기존 build `1.0.0`을 조회해 `1.0.1`로 증가했고 App Store Connect 업로드 수락을 확인했다. IPA SHA-256 `24b28a743d044d7a1997b52c7b86e5fe4f65a9037b3a008ad5161d21bebd90a9`. 이 후속 빌드의 processingState는 별도 미확인이며 앞선 `1.0.0`의 VALID 결과로 대체하지 않는다.

- **Dev 자동 업로드 및 ASC 처리 확인:** `develop`의 `4c63bd892e06da56585d8a83142bba4443784ab5`, 실행 `36565189816` 성공. Dev IPA SHA-256 `b157f1d4141a1d35cd7abf8b097588bfb0ab1dd86cd2b81eeecb8a167a0540ed`, build `1.0.0`. ASC build ID `3bcc2c57-c2a9-45aa-be0f-db151b81d412`, processingState `VALID`, expired=false를 담당자가 GET으로 확인했다. 앱 betaGroups, 빌드 betaGroups, individualTesters 모두 0개다. 내부·외부 beta 상태는 `MISSING_EXPORT_COMPLIANCE`이며 아직 테스트 가능 상태가 아니다. `autoNotifyEnabled=true`이므로 향후 수출 규정 입력·테스터 연결 전에 재확인이 필요하다. 현재 업로드 코드는 새 그룹이 생기면 실패한다. Prod 업로드 및 main 반영은 하지 않았다.

- **Hosted Dev·Prod 서명 검증 통과:** 실행 `36562673588`, attempt 3, 앱 SHA `4c63bd892e06da56585d8a83142bba4443784ab5`. 두 작업 모두 match identity 설치 및 archive/IPA 검증 sentinel을 출력하고 성공했다. 두 대상 build `1.0.0`, `DELIVERY_MODE=verify`이며 업로드 실행 증거는 아니다.
- Prod IPA SHA-256: `56e641e1d24ec934c26d56ab9e85a8d9d6a755de68d27574917f69bb8fa410a9`.
- Dev IPA SHA-256: `1912d3cd0268f94cfed72f71e7a187923eef2a2adf062d7a1ae55baca30b49e5`.

- 최초 hosted 실행에서 Prod bundle 검색이 Dev까지 반환해 정확한 bundleId 필터를 추가했다. 앱 ID 검증과 중복·누락 거절은 유지한다.
- CI SSH 파일 끝 개행 누락을 로컬 ssh-keygen으로 재현하고 복원했다. 새 read-only deploy key ID `164810680`으로 실제 ls-remote를 검증했다. 기존 key는 삭제하지 않았다.
- bootstrap은 암호 파일에 `.strip`을 적용하므로 CI MATCH_PASSWORD도 동일하게 정규화해 재등록했다. 이후 Dev·Prod 모두 clone과 복호화에 성공했다.
- OpenSSL PKCS12 parse 성공만으로 macOS import를 보장할 수 없었다. hosted에서 MAC verification 실패를 확인해 기존 키·인증서를 macOS native export로 재포장했다. 서명 저장소 `545b028c079eb91982a1490703eb72b66a8d2d7e`는 암호화 P12 한 파일만 변경한다. 담당자는 암호화 전·재복호화 후·원격 clone 후 임시 keychain import와 예상 identity 확인을 통과했다. 새 자료의 hosted archive/export 결과는 실행 `36562673588` 재시도에서 별도로 확인한다.

아래 최초 준비 기록은 당시 상태이며, 위 후속 검증과 구분한다.

GitHub deploy key ID `164494925`, 제목 `balmatchum-app-staging-match-readonly`, `read_only=true`를 API로 확인했다. 하지만 해당 private key는 GitHub Secret에만 있고 로컬 SSH agent는 identity 0개다. 따라서 **그 CI key로 실제 clone/decrypt/import한 증거는 아직 없다**. GitHub API 사용자 인증으로 원격 blob을 검증한 것과 deploy key 접근을 혼동하지 않는다.

리드가 staging MATCH_PASSWORD를 이번 로컬 파일에서 동기화했다고 전달했다. 값은 조회하지 않았다. 다음 hosted verify 실행이 MATCH_GIT_PRIVATE_KEY clone → MATCH_PASSWORD 복호화 → 임시 keychain import → 실제 signed archive/export까지 증명하는 최초 단계다.

## ASC 상태

Dev `6816329763` / `com.beomq.balmatchum.dev`, Prod `6816329577` / `com.beomq.balmatchum` 모두 GET 200. 각 betaGroups 1페이지, 0개, next 없음. 현재 내부 자동 배포 그룹은 없으며 업로드 직전 다시 검사한다. 새 그룹이 하나라도 생기면 현재 구현은 fail closed한다. API key/JWT 원문은 로그·argv·파일로 노출하지 않았다.

## 앱 원래 checkout의 준비 파일 — 미커밋

- `.github/workflows/apple-upload.yml`
- `tool/apple/run_delivery.rb`
- `tool/apple/prepare_match_staging.rb`
- `fastlane/apple/Fastfile`
- `fastlane/apple/asc_preflight.rb`
- `fastlane/apple/asc_preflight_test.rb`

workflow는 develop/main push에서 같은 checkout SHA의 analyze/test를 먼저 실행하고 readonly match, 기존 archive/export 설정을 사용한다. manual 실행은 항상 verify 모드다. push도 `APPLE_UPLOAD_ENABLED=true`가 설정되기 전에는 실제 signed archive/export까지만 수행한다. 이 초기 활성화 스위치는 hosted proof 이전 업로드 방지용이며 매 실행 GitHub reviewer 클릭을 요구하지 않는다. 현재 변수는 등록하지 않았다.

임시 keychain·p8·SSH key는 권한 제한 temp에만 기록하고 ensure로 정리한다. match는 readonly이며 기존 환경의 두 bundle만 가져온다. ASC 그룹 검사는 archive 전과 업로드 직전에 모두 수행한다. upload 모드에서는 skip_submission, skip_waiting_for_build_processing, distribute_external=false, notify_external_testers=false, submit_beta_review=false로 client 배포·심사를 억제한다. ASC 그룹 설정이 다시 생기면 업로드 전에 실패한다. release 호출은 없다.

버전은 ASC의 해당 앱 전체 build 이력을 읽어 최대값 다음 `major.minor.patch`를 두 번들에 공유한다. 첫 성분은 1~9999, 나머지는 0~99이며 자리올림한다. 범위를 벗어난 기존 이력이나 상한 소진은 실패 처리한다. 업로드 직전 이력을 다시 읽어 번호가 이미 사용됐다면 재빌드를 요구한다. 동일 브랜치 실행은 concurrency로 직렬화한다. 외부 업로더와의 원자적 번호 예약을 보장하지 않으며 ASC 처리 지연 중 중복은 서버가 최종 판정한다.

근거: https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html 의 CFBundleVersion 항목은 4/2/2자리 제한을 명시한다. 기존 epoch 정수는 제거했다. 실제 GET으로 두 앱 build 이력 0개, 다음 번호 `1.0.0`을 확인했다. 이는 API 조회 및 형식 검증이며 업로드 수락 증거는 아니다.

후속 구현 파일: `tool/apple/build_number.rb`, `build_number_test.rb`, `verify_package.rb`. 번호 테스트는 3 tests / 6 assertions 통과. 새 패키지 검증기를 기존 Dev archive와 추출 IPA에 실제 실행해 bundle·공유 버전·companion·codesign·서명 및 profile entitlement·privacy plist 검증 통과, IPA SHA-256 `58a9f684d73c74d5085a9185c8da8c4413fabafddab2abb7f99302e6fd7595ea`를 확인했다. 기존 산출물 검증이며 새 hosted build 증거가 아니다.

`tool/apple/delivery_target.rb`는 lane 진입 시 upload의 Dev→`refs/heads/develop`, Prod→`refs/heads/main`을 강제한다. verify는 develop/main/`chore/cicd-validation`만 허용한다. 임의 환경변수로 target을 바꿔도 ref가 맞지 않으면 서명·업로드 전에 실패한다. 가드 테스트 2 tests / 9 assertions 통과.

hosted 성공 후 `apple-output`의 archive, IPA, `identity-evidence.json`만 명시적으로 선택해 7일 artifact로 보존한다. export 로그와 DistributionSummary/ExportOptions는 제외하며 임시 keychain/p8/SSH key도 포함하지 않는다. identity evidence에는 bundle/build/source SHA/IPA SHA-256/archive 및 IPA 검증 결과가 들어간다. 로컬 기존 패키지에 실행한 evidence의 SHA는 null이므로 hosted source 증거로 쓰지 않는다. match 뒤 예상 지문이 임시 keychain에 실제 설치됐는지 검사하고 `APPLE_MATCH_READONLY_IMPORT_VERIFIED`를 출력한다. 최종 패키지 검증은 `APPLE_SIGNED_PACKAGE_VERIFIED`를 출력한다.

독립 코드 리뷰 `st_01a0ecda`에서 CRITICAL/HIGH 없음. 유일한 수정 요청인 artifact 전체 디렉터리 보존은 위 세 종류 allowlist로 변경했고 actionlint 및 diff check 종료 0이다. 리뷰 원문은 `.omo/evidence/apple-delivery-code-review.md`이며 수정 전 판정을 기록하므로 해결 증거는 이 후속 기록과 현재 workflow를 함께 본다.

리드 통합 manifest: `.github/workflows/apple-upload.yml`, `fastlane/apple/{Fastfile,asc_preflight.rb,asc_preflight_test.rb}`, `tool/apple/{run_delivery.rb,build_number.rb,build_number_test.rb,delivery_target.rb,delivery_target_test.rb,verify_package.rb}`, 이 문서. `prepare_match_staging.rb`는 완료된 로컬 bootstrap 도구이며 CI에서 실행하지 않는다. 기존 `ios/Signing` 4파일과 watch 통합은 선행 조건이다.

## 로컬 검사와 남은 gate

- preflight fake 테스트: 4 tests / 5 assertions, failure 0, error 0.
- Ruby 문법 검사 및 actionlint 1.7.7: 종료 0.
- 실제 Fastfile 로딩 후 `ios upload_only` lane 인식 확인. 초기 bare require의 로컬 Bundler 로딩 문제는 Bundler 선로드 및 Fastlane.load_actions 호출로 해결했다.
- Ruby/YAML LSP 미설치, 추가 설치 없음.
- **hosted signed build는 미실행**이다. 앱 파일을 커밋하거나 workflow dispatch하지 않았다. integration committer인 리드가 위 파일을 통합한 후 manual verify Dev/Prod 실행이 가장 빠른 다음 gate다.
- hosted 두 대상 성공 후 deploy key 접근·match import·Xcode 26.3 signed archive/export 로그를 확인하고, ASC build-number 정책과 업로드할 정확한 SHA/앱을 확정한 뒤 활성화한다. upload 성공이나 TestFlight processing 성공을 아직 주장하지 않는다.

원래 checkout 및 integration worktree는 커밋·push하지 않았다. signing 저장소 게시만 승인 범위로 수행했다.
