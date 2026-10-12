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

    /// プリセットや細分化など「選択中の1つがハイライトされるチップ」の共通装飾
    func chip(selected: Bool) -> some View {
        background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .pointingHandCursor()
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
                        value = min(max(stepped, range.lowerBound), range.upperBound)
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
            .contentShape(Rectangle())
            .pointingHandCursor()
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(isOn ? Text("On") : Text("Off"))
            .onTapGesture { isOn.toggle() }
            .accessibilityAction { isOn.toggle() }
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
        .contentShape(Rectangle())
        .pointingHandCursor()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
        .onTapGesture { isOn.toggle() }
        .accessibilityAction { isOn.toggle() }
    }
}
