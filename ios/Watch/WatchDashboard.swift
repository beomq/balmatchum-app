import SwiftUI
import WatchSyncContract

/// Renders only an authenticated snapshot supplied by the connectivity boundary.
struct WatchDashboard: View {
    let snapshot: DisplaySnapshot?
    let connectionMessage: String
    let storageError: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text(connectionMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if storageError {
                    Text("기록 저장 상태를 확인할 수 없어요")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if let snapshot, snapshot.authState == .authenticated {
                    if let steps = snapshot.dailySteps {
                        HStack(spacing: 6) {
                            VStack(spacing: 3) {
                                Text(dayLabel(steps.date))
                                    .font(.caption)
                                Text(steps.count, format: .number)
                                    .font(.system(.title2, design: .rounded).bold())
                                    .minimumScaleFactor(0.7)
                                    .lineLimit(1)
                                    .accessibilityLabel("\(dayLabel(steps.date)) \(steps.count)걸음")
                            }
                            dogImage(snapshot.selectedDog)
                        }
                        dogName(snapshot.selectedDog)
                        Text(updatedLabel(steps.observedAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("걸음 정보 없음")
                        dog(snapshot.selectedDog)
                        Text("iPhone에서 건강 정보 접근을 확인해 주세요.")
                            .font(.caption2)
                    }
                } else {
                    Image(systemName: "iphone.and.arrow.forward")
                        .font(.largeTitle)
                        .accessibilityHidden(true)
                    Text("iPhone 연결이 필요해요")
                    Text("iPhone에서 로그인 상태를 확인해 주세요.")
                        .font(.caption2)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
        }
    }

    private func dayLabel(_ date: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date()) == date ? "오늘 걸음" : "최근 걸음"
    }

    private func updatedLabel(_ timestamp: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = parser.date(from: timestamp)
        if date == nil {
            parser.formatOptions = [.withInternetDateTime]
            date = parser.date(from: timestamp)
        }
        guard let date else { return "갱신 시각 확인 필요" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "M월 d일 HH:mm"
        return "갱신 \(formatter.string(from: date)) · 한국 시간"
    }

    @ViewBuilder private func dog(_ selected: DisplaySnapshot.Dog?) -> some View {
        dogImage(selected)
        dogName(selected)
    }

    @ViewBuilder private func dogImage(_ selected: DisplaySnapshot.Dog?) -> some View {
        if let selected, let asset = DogAsset.name(for: selected.assetKey) {
            Image(asset)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 60, height: 60)
                .accessibilityLabel(selected.displayName)
        }
    }

    @ViewBuilder private func dogName(_ selected: DisplaySnapshot.Dog?) -> some View {
        if let selected {
            // Asset resolution is deliberately explicit; no other breed is substituted.
            if DogAsset.name(for: selected.assetKey) == nil {
                Text("강아지 이미지 준비 중")
                    .font(.caption)
            }
            Text(selected.displayName)
                .font(.headline)
        } else {
            Text("선택된 강아지가 없어요")
                .font(.caption)
        }
    }
}
