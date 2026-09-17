import SwiftUI

/// "Feedback? DM us" — opens the Instagram app directly to the profile (so the visitor
/// can just tap "Message") if installed, otherwise falls back to the web profile page.
/// No in-app form, no server of ours collecting anything — feedback goes straight to
/// the one place it's actually read: @Obszoen_official's DMs.
enum InstagramLink {
    static let username = "Obszoen_official"

    static func open() {
        let appURL = URL(string: "instagram://user?username=\(username)")!
        let webURL = URL(string: "https://instagram.com/\(username)")!
        if UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else {
            UIApplication.shared.open(webURL)
        }
    }
}

struct FeedbackBox: View {
    var body: some View {
        Button {
            InstagramLink.open()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "paperplane.fill")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Feedback? Schreib uns.").font(.caption).fontWeight(.semibold)
                    Text("DM auf Instagram @\(InstagramLink.username)").font(.caption2).opacity(0.75)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).opacity(0.6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Brand.rose.opacity(0.18))
            .foregroundStyle(Brand.rose)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
