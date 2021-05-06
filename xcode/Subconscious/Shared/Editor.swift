//
//  Editor.swift
//  Subconscious (iOS)
//
//  Created by Gordon Brander on 4/27/21.
//

import Foundation
import Combine
import SwiftUI
import os

//  MARK: Actions
enum EditorAction {
    case titleField(_ action: TextFieldWithToggleAction)
    case edit(SubconsciousDocument)
    case save(SubconsciousDocument)
    case cancel
    case clear
    case selectTitle(_ text: String)
    case requestSave(SubconsciousDocument)
    case queryTitleSuggestions(_ query: String)
    case requestTitleMatch(_ title: String)
    case requestEditorUnpresent
    case updateTitle(_ title: String)
    case setBody(body: String)
    case setTitleSuggestions(_ suggestions: [Suggestion])
}


//  MARK: State
struct EditorState {
    var titleField = TextFieldWithToggleState(
        text: "",
        placeholder: ""
    )
    var body = ""
    var titleSuggestions: [Suggestion] = [
        .query(.init(text: "Evolution")),
        .query(.init(text: "Evolution selects for good enough")),
        .query(.init(text: "The Evolution of Civilizations￼"))
    ]
}


func tagTitleField(_ action: TextFieldWithToggleAction) -> EditorAction {
    switch action {
    case .setText(let text):
        return .updateTitle(text)
    default:
        return EditorAction.titleField(action)
    }
}


//  MARK: Reducer
func editorReducer(
    state: inout EditorState,
    action: EditorAction,
    environment: AppEnvironment
) -> AnyPublisher<EditorAction, Never> {
    switch action {
    case .titleField(let action):
        return updateTextFieldWithToggle(
            state: &state.titleField,
            action: action
        ).map(tagTitleField).eraseToAnyPublisher()
    case .updateTitle(let title):
        let setTitle = EditorAction.titleField(.setText(title))
        let querySuggestions = EditorAction.queryTitleSuggestions(title)
        return Publishers.Merge(
            Just(setTitle),
            Just(querySuggestions)
        ).eraseToAnyPublisher()
    case .setBody(let body):
        state.body = body
    case .setTitleSuggestions(let suggestions):
        state.titleSuggestions = suggestions
    case .edit(let document):
        let setTitle = Just(
            EditorAction.titleField(.setText(document.title))
        )
        let setBody = Just(
            EditorAction.setBody(body: document.content.description)
        )
        return Publishers.Merge(setTitle, setBody)
            .eraseToAnyPublisher()
    case .save(let document):
        let save = Just(EditorAction.requestSave(document))
        let unpresent = Just(EditorAction.requestEditorUnpresent)
        let clear = Just(EditorAction.clear).delay(
            for: .milliseconds(500),
            scheduler: RunLoop.main
        )
        return Publishers.Merge3(save, unpresent, clear)
            .eraseToAnyPublisher()
    case .cancel:
        let unpresent = Just(EditorAction.requestEditorUnpresent)
        // Delay for a bit. Should clear just after sheet animation completes.
        // Note that SwiftUI animations don't yet have reasonable
        // onComplete handlers, so we're making do.
        let clear = Just(EditorAction.clear).delay(
            for: .milliseconds(500),
            scheduler: RunLoop.main
        )
        return Publishers.Merge(unpresent, clear).eraseToAnyPublisher()
    case .clear:
        let setTitle = Just(
            EditorAction.titleField(.setText(""))
        )
        let setBody = Just(
            EditorAction.setBody(body: "")
        )
        let setSuggestions = Just(
            EditorAction.setTitleSuggestions([])
        )
        return Publishers.Merge3(setTitle, setBody, setSuggestions)
            .eraseToAnyPublisher()
    case .selectTitle(let text):
        let setTitle = Just(EditorAction.titleField(.setText(text)))
        let requestMatch = Just(EditorAction.requestTitleMatch(text))
        let closeSuggestions = Just(
            EditorAction.titleField(.setToggle(isActive: false))
        )
        return Publishers.Merge3(setTitle, requestMatch, closeSuggestions)
            .eraseToAnyPublisher()
    case .queryTitleSuggestions(let query):
        return environment.fetchSuggestions(query: query)
            .map({ suggestions in .setTitleSuggestions(suggestions) })
            .eraseToAnyPublisher()
    case .requestSave:
        environment.logger.warning(
            """
            EditorAction.requestSave
            should be handled by the parent view.
            """
        )
    case .requestTitleMatch:
        environment.logger.warning(
            """
            EditorAction.requestTitleMatch
            should be handled by parent view.
            """
        )
    case .requestEditorUnpresent:
        environment.logger.warning(
            """
            EditorAction.requestEditorUnpresent
            should be handled by the parent view.
            """
        )
    }
    return Empty().eraseToAnyPublisher()
}


//  MARK: View
struct EditorView: View {
    var state: EditorState
    var send: (EditorAction) -> Void
    var save: LocalizedStringKey = "Save"
    var cancel: LocalizedStringKey = "Cancel"
    var edit: LocalizedStringKey = "Edit"
    var titlePlaceholder: LocalizedStringKey = "Title:"
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(cancel) {
                    send(.cancel)
                }
                Spacer()
                Button(action: {
                    send(.save(
                        SubconsciousDocument(
                            title: state.titleField.text,
                            markup: state.body
                        )
                    ))
                }) {
                    Text(save)
                }
            }.padding(16)
            HStack(spacing: 8) {
                Text(titlePlaceholder)
                    .foregroundColor(.secondary)
                TextFieldWithToggleView(
                    state: state.titleField,
                    send: address(
                        send: send,
                        tag: tagTitleField
                    )
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            Group {
                if state.titleField.isToggleActive {
                    List(state.titleSuggestions) { suggestion in
                        Button(
                            action: {
                                send(.selectTitle(suggestion.text))
                            },
                            label: {
                                SuggestionRowView(suggestion: suggestion)
                            }
                        )
                    }
                } else {
                    TextEditor(
                        text: Binding(
                            get: { state.body },
                            set: { value in
                                send(EditorAction.setBody(body: value))
                            }
                        )
                    )
                    // Note that TextEditor has some internal padding
                    // about 4px, eyeballing it with a straightedge.
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

struct EditorView_Previews: PreviewProvider {
    static var previews: some View {
        EditorView(
            state: EditorState(),
            send: { action in }
        )
    }
}
