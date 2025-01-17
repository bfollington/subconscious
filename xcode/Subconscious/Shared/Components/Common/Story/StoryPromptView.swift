//
//  StoryPromptView.swift
//  Subconscious (iOS)
//
//  Created by Gordon Brander on 7/26/22.
//

import SwiftUI

/// A story is a single update within the FeedView
struct StoryPromptView: View {
    var story: StoryPrompt
    var action: (MemoAddress, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AppTheme.unit) {
                Text("@cdata")
                Text("at")
                    .foregroundColor(Color.secondary)
                Text(story.entry.modified.formatted())
                    .foregroundColor(Color.secondary)
                Spacer()
            }
            .font(.caption)
            .padding()
            .frame(height: AppTheme.unit * 11)
            Divider()
            VStack(alignment: .leading, spacing: AppTheme.unit4) {
                Text(story.prompt)
                Button(
                    action: {
                        action(
                            story.entry.address,
                            story.entry.title
                        )
                    },
                    label: {
                        TranscludeView(
                            pfp: Image("pfp-dog"),
                            petname: "@doge",
                            slug: story.entry.address.slug.toSlashlink(),
                            title: story.entry.title,
                            excerpt: story.entry.excerpt
                        )
                    }
                )
                .buttonStyle(.plain)
            }
            .padding()
            Divider()
            HStack {
                Button(
                    action: {
                        action(
                            story.entry.address,
                            story.entry.title
                        )
                    },
                    label: {
                        Text("Open")
                    }
                )
                Spacer()
            }
            .padding()
            .frame(height: AppTheme.unit * 15)
            ThickDividerView()
        }
    }
}

struct StoryPromptView_Previews: PreviewProvider {
    static var previews: some View {
        StoryPromptView(
            story: StoryPrompt(
                entry: EntryStub(
                    MemoEntry(
                        address: MemoAddress(
                            slug: Slug("meme")!,
                            audience: .public
                        ),
                        contents: Memo(
                            contentType: ContentType.subtext.rawValue,
                            created: Date.now,
                            modified: Date.now,
                            title: "Meme",
                            fileExtension: ContentType.subtext.fileExtension,
                            additionalHeaders: [],
                            body: """
                            The gene, the DNA molecule, happens to be the replicating entity that prevails on our own planet. There may be others.

                            But do we have to go to distant worlds to find other kinds of replicator and other, consequent, kinds of evolution? I think that a new kind of replicator has recently emerged on this very planet. It is staring us in the face.
                            """
                        )
                    )
                ),
                prompt: "Can I invert this?"
            ),
            action: { link, fallback in }
        )
    }
}
