import SwiftUI

// MARK: - Pointing Hand Cursor
// 以前は onHover + NSCursor.push/pop で実装していたが、ホバー中にビューが消えると
// pop されずカーソルが指のまま残るため、macOS 15 の pointerStyle に置き換えた

extension View {
    func pointingHandCursor() -> some View {
        pointerStyle(.link)
    }

    /// onTapGesture だけだと VoiceOver からボタンとして扱われないため、
    /// タップ処理とアクセシビリティ情報をまとめて付ける
    func accessibleTap(
        _ label: Text, value: Text? = nil, selected: Bool = false, action: @escaping () -> Void
    ) -> some View {
        onTapGesture(perform: action)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value ?? Text(""))
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { action() }
    }

    /// accessibleTap のトグル版。MiniSwitch と CheckBox で共有する
    func accessibleToggle(_ isOn: Binding<Bool>, label: Text? = nil) -> some View {
        contentShape(Rectangle())
            .pointingHandCursor()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label ?? Text(""))
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(isOn.wrappedValue ? Text("On") : Text("Off"))
            .onTapGesture { isOn.wrappedValue.toggle() }
            .accessibilityAction { isOn.wrappedValue.toggle() }
    }

    /// プリセットや細分化など「選択中の1つがハイライトされるチップ」の共通装飾
    /// - Parameter outlined: リストの行のように枠線が要らない場合は false
    func chip(selected: Bool, outlined: Bool = true) -> some View {
        modifier(ChipStyle(selected: selected, outlined: outlined))
    }
}

// MARK: - Custom Slider
// macOS の SwiftUI 標準 Slider はポップオーバー内でトラックが二重描画される
// 問題があるため、GeometryReader + DragGesture で独自実装。

struct CustomSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// 値の刻み。BPM は整数、音量は 0.01 刻みにしたいので呼び出し側で指定する
    var step: Double = 1
    var tint: Color = .accentColor
    /// VoiceOver の上下スワイプ1回で動かす量。省略時は step
    var accessibilityStep: Double?

    private let trackHeight: CGFloat = 4
    private let thumbSize: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width - thumbSize
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let offset = width * CGFloat(fraction)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: trackHeight)
                    .padding(.horizontal, thumbSize / 2)

                Capsule()
                    .fill(tint)
                    .frame(width: offset + thumbSize / 2, height: trackHeight)
                    .padding(.leading, thumbSize / 2)

                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: offset)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .pointingHandCursor()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let fraction = Double((drag.location.x - thumbSize / 2) / width)
                        let clamped = min(max(fraction, 0), 1)
                        let raw = clamped * (range.upperBound - range.lowerBound) + range.lowerBound
                        let stepped = (raw / step).rounded() * step
                        value = stepped.clamped(to: range)
                    }
            )
        }
        // VoiceOver では調整可能な要素として扱い、上下スワイプで1段階ずつ動かせるようにする
        .accessibilityElement(children: .ignore)
        .accessibilityAdjustableAction { direction in
            let delta = accessibilityStep ?? step
            switch direction {
            case .increment: value = min(value + delta, range.upperBound)
            case .decrement: value = max(value - delta, range.lowerBound)
            @unknown default: break
            }
        }
    }
}

// MARK: - Mini Switch / Check Box
// AppKit 由来の Toggle は ImageRenderer（--snapshot）で描画されないため、
// スライダーと同様に SwiftUI だけで描く

struct MiniSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.3))
            .frame(width: 26, height: 15)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                    .padding(2)
            }
            .animation(.easeOut(duration: 0.12), value: isOn)
            .accessibleToggle($isOn)
    }
}

struct CheckBox: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                .foregroundColor(isOn ? .accentColor : .secondary)
            Text(title)
        }
        .accessibleToggle($isOn, label: Text(title))
    }
}

// MARK: - Popover Icon Button

/// 小さなグレーのアイコンを押すとポップオーバーを開くボタン（曲リスト・ショートカット一覧）
struct PopoverIconButton<Content: View>: View {
    let systemName: String
    var size: CGFloat = 11
    let help: LocalizedStringKey
    var label: Text?
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size))
                .foregroundColor(.secondary)
                .frame(width: size + 10, height: size + 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label ?? Text(help))
        .pointingHandCursor()
        .popover(isPresented: $isPresented, arrowEdge: .bottom, content: content)
    }
}

/// 「コントラストを上げる」設定のときは枠線と選択色を濃くして、選択状態を見分けやすくする
private struct ChipStyle: ViewModifier {
    let selected: Bool
    let outlined: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let strong = contrast == .increased
        content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.accentColor.opacity(strong ? 0.3 : 0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        outlined
                            ? (selected ? Color.accentColor.opacity(strong ? 1 : 0.4) : Color.secondary.opacity(strong ? 0.6 : 0.2))
                            : .clear,
                        lineWidth: strong ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
            .pointingHandCursor()
    }
}

// MARK: - Practice Time

/// 練習時間を "2時間15分" / "2h 15m" のように言語に合わせて短く表す（目標の行で「実績 / 目標」を 1 行に収めるため）
enum PracticeTime {
    static func format(_ seconds: Double, locale: Locale? = nil) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        if let locale {
            var calendar = Calendar.current
            calendar.locale = locale
            formatter.calendar = calendar
        }
        return formatter.string(from: seconds) ?? ""
    }
}
