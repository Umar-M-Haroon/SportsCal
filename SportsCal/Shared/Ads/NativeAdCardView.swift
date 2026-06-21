//
//  NativeAdCardView.swift
//  SportsCal
//
//  Created by Umar Haroon on 2026-04-08.
//

#if os(iOS)
import SwiftUI
import GoogleMobileAds

/// A SwiftUI wrapper that renders a Google native ad using the required NativeAdView.
/// Styled to match the game card appearance (neutral gray background, hidden separator).
/// The card scales dynamically based on the ad's media content.
struct NativeAdCardView: View {
    let nativeAd: NativeAd

    var body: some View {
        VStack(spacing: 4) {
            NativeAdRepresentable(nativeAd: nativeAd)
            // The ad slot doubles as a clean upgrade surface — only free users
            // ever see it. An explicit tap goes straight to the paywall (not
            // throttled) via a notification ContentView observes.
            Button {
                MonetizationTelemetry.adUpsellTapped()
                NotificationCenter.default.post(name: .requestPaywall, object: nil)
            } label: {
                Text("Remove ads with Pro")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(Color.gray.opacity(0.15))
        .listRowSeparator(.hidden)
    }
}

// MARK: - UIViewRepresentable

private struct NativeAdRepresentable: UIViewRepresentable {
    let nativeAd: NativeAd

    func makeUIView(context: Context) -> NativeAdView {
        let adView = NativeAdView()
        adView.backgroundColor = .clear

        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 8
        container.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: adView.topAnchor, constant: 8),
            container.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 8),
            container.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -8),
            container.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: -8),
        ])

        // Media view — full width, scales with aspect ratio
        let mediaView = MediaView()
        mediaView.contentMode = .scaleAspectFit
        mediaView.clipsToBounds = true
        mediaView.layer.cornerRadius = 8
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        // Minimum 120pt for AdMob video requirement, but can grow
        mediaView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        container.addArrangedSubview(mediaView)
        adView.mediaView = mediaView

        // Text row: icon + headline/body + CTA
        let textRow = UIStackView()
        textRow.axis = .horizontal
        textRow.alignment = .center
        textRow.spacing = 8
        container.addArrangedSubview(textRow)

        // Icon
        let iconView = UIImageView()
        iconView.contentMode = .scaleAspectFit
        iconView.layer.cornerRadius = 6
        iconView.clipsToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 32).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 32).isActive = true
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        textRow.addArrangedSubview(iconView)
        adView.iconView = iconView

        // Text stack: headline + body
        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.spacing = 2
        textRow.addArrangedSubview(textStack)

        let headlineLabel = UILabel()
        headlineLabel.font = .preferredFont(forTextStyle: .subheadline, compatibleWith: nil)
        headlineLabel.font = .systemFont(ofSize: headlineLabel.font.pointSize, weight: .semibold)
        headlineLabel.numberOfLines = 2
        textStack.addArrangedSubview(headlineLabel)
        adView.headlineView = headlineLabel

        let bodyLabel = UILabel()
        bodyLabel.font = .preferredFont(forTextStyle: .caption1)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 2
        textStack.addArrangedSubview(bodyLabel)
        adView.bodyView = bodyLabel

        // CTA button
        let ctaButton = UIButton(type: .system)
        ctaButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        ctaButton.setTitleColor(.white, for: .normal)
        ctaButton.backgroundColor = .systemBlue
        ctaButton.layer.cornerRadius = 6
        ctaButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        ctaButton.isUserInteractionEnabled = false
        ctaButton.setContentHuggingPriority(.required, for: .horizontal)
        ctaButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        textRow.addArrangedSubview(ctaButton)
        adView.callToActionView = ctaButton

        // "Ad" badge — overlaid on top-right of media
        let adBadge = UILabel()
        adBadge.text = "Ad"
        adBadge.font = .systemFont(ofSize: 10, weight: .bold)
        adBadge.textColor = .white
        adBadge.backgroundColor = UIColor.systemYellow
        adBadge.textAlignment = .center
        adBadge.layer.cornerRadius = 3
        adBadge.clipsToBounds = true
        adBadge.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(adBadge)

        NSLayoutConstraint.activate([
            adBadge.topAnchor.constraint(equalTo: mediaView.topAnchor, constant: 6),
            adBadge.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor, constant: -6),
            adBadge.widthAnchor.constraint(equalToConstant: 22),
            adBadge.heightAnchor.constraint(equalToConstant: 16),
        ])

        return adView
    }

    func updateUIView(_ adView: NativeAdView, context: Context) {
        adView.nativeAd = nativeAd

        (adView.iconView as? UIImageView)?.image = nativeAd.icon?.image
        (adView.headlineView as? UILabel)?.text = nativeAd.headline
        (adView.bodyView as? UILabel)?.text = nativeAd.body
        (adView.callToActionView as? UIButton)?.setTitle(nativeAd.callToAction, for: .normal)
        adView.callToActionView?.isHidden = nativeAd.callToAction == nil

        // Hide icon if not provided
        adView.iconView?.isHidden = nativeAd.icon == nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NativeAdView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let fittingSize = uiView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: min(max(fittingSize.height, 160), 200))
    }
}
#endif
