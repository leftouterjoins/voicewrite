import SwiftUI

/// A view that displays text with word-level animations when content changes.
/// Words that remain unchanged stay stable, while new/changed words animate in
/// with a smooth "pop-in" effect (fade + scale).
struct AnimatedTextView: View {
    let text: String

    @State private var displayedWords: [AnimatedWord] = []

    var body: some View {
        WrappingHStack(alignment: .leading, horizontalSpacing: 5, verticalSpacing: 4) {
            ForEach(displayedWords) { word in
                Text(word.text)
                    .opacity(word.opacity)
                    .scaleEffect(word.scale)
            }
        }
        .onChange(of: text) { oldValue, newValue in
            updateWords(from: oldValue, to: newValue)
        }
        .onAppear {
            initializeWords()
        }
    }

    private func initializeWords() {
        displayedWords = parseWords(from: text).map { word in
            AnimatedWord(text: word, opacity: 1.0, scale: 1.0)
        }
    }

    private func updateWords(from oldText: String, to newText: String) {
        let oldWords = parseWords(from: oldText)
        let newWords = parseWords(from: newText)

        // Find longest common prefix
        var commonPrefixLength = 0
        for (index, newWord) in newWords.enumerated() {
            if index < oldWords.count && oldWords[index] == newWord {
                commonPrefixLength = index + 1
            } else {
                break
            }
        }

        // Build new displayed words array
        var updatedWords: [AnimatedWord] = []

        // Keep unchanged words with their existing state
        for i in 0..<min(commonPrefixLength, displayedWords.count) {
            updatedWords.append(displayedWords[i])
        }

        // Add new/changed words with initial animation state
        for i in commonPrefixLength..<newWords.count {
            updatedWords.append(AnimatedWord(
                text: newWords[i],
                opacity: 0.0,  // Start invisible
                scale: 0.8     // Start slightly smaller
            ))
        }

        displayedWords = updatedWords

        // Animate new words in after a brief delay
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(10))

            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                for i in commonPrefixLength..<displayedWords.count {
                    displayedWords[i].opacity = 1.0
                    displayedWords[i].scale = 1.0
                }
            }
        }
    }

    private func parseWords(from text: String) -> [String] {
        // Split by whitespace but preserve punctuation attached to words
        text.split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
    }
}

/// Represents a single word with animation properties
struct AnimatedWord: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var opacity: Double
    var scale: Double

    static func == (lhs: AnimatedWord, rhs: AnimatedWord) -> Bool {
        lhs.id == rhs.id && lhs.text == rhs.text
    }
}

/// A custom layout that wraps children horizontally, creating new rows as needed
struct WrappingHStack: Layout {
    var alignment: HorizontalAlignment = .leading
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(
            in: proposal.width ?? .infinity,
            subviews: subviews
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(in: bounds.width, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            let position = result.positions[index]
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct LayoutResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
    }

    private func computeLayout(in maxWidth: CGFloat, subviews: Subviews) -> LayoutResult {
        var result = LayoutResult()

        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            // Check if we need to wrap to next line
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += lineHeight + verticalSpacing
                lineHeight = 0
            }

            result.positions.append(CGPoint(x: x, y: y))

            lineHeight = max(lineHeight, size.height)
            x += size.width + horizontalSpacing
            maxX = max(maxX, x - horizontalSpacing)
        }

        result.size = CGSize(width: maxX, height: y + lineHeight)
        return result
    }
}

#Preview {
    VStack(spacing: 20) {
        AnimatedTextView(text: "Hello world this is a test")
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))

        AnimatedTextView(text: "The quick brown fox jumps over the lazy dog and runs away")
            .frame(maxWidth: 200)
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .padding()
}
