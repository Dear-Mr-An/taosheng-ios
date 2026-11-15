import SwiftUI

// MARK: - 通用底部抽屉（原版是 ModalBottomSheet：背景压暗、白色面板、顶部大圆角、拖动条）

struct RsBottomSheet<Content: View>: View {
    var tall: Bool = false
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var appeared = false
    @State private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black.opacity(appeared ? 0.32 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { close() }

                panel(maxHeight: geo.size.height * (tall ? 0.94 : 0.86))
                    .offset(y: appeared ? drag : geo.size.height)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.24)) { appeared = true }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func close() {
        withAnimation(.easeIn(duration: 0.18)) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onClose() }
    }

    private func panel(maxHeight: CGFloat) -> some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Rs.separator)
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(dragGesture)

            ScrollView(showsIndicators: false) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: maxHeight)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Rs.card)
                .ignoresSafeArea(edges: .bottom)
        )
        .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { v in
                if v.translation.height > 0 { drag = v.translation.height }
            }
            .onEnded { v in
                if v.translation.height > 110 { close() } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { drag = 0 }
                }
            }
    }
}

// MARK: - 流式排布（原版 FlowRow：一行能放两个就放两个）

struct RsFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineH + lineSpacing
                lineH = 0
            }
            x += size.width + spacing
            lineH = max(lineH, size.height)
        }
        return CGSize(width: maxWidth, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineH: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + bounds.width {
                x = bounds.minX
                y += lineH + lineSpacing
                lineH = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineH = max(lineH, size.height)
        }
    }
}
