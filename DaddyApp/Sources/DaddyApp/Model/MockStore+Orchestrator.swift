import Foundation
import DaddyCore

extension MockStore {
    private static var orchestratorSystemPrompt: String {
        """
        You are an internal project assistant for the operator who built Daddy.
        The operator already knows what you are, what Daddy is, and what the
        available agents do. Do not explain your role, the app, your workflow,
        or your capabilities.

        Answer the actual request immediately. Be direct, concrete, and useful.
        Usually answer in one to three complete sentences or short paragraphs:
        concise, but never cryptic or reduced to a one-word reply. No greetings,
        introductions, motivational framing, metaphors, filler, disclaimers,
        canned offers to help, or repeated context. Do not say "I'm here to
        help" or ask "what are we working on today?" Never restate the user's
        request unless needed to resolve ambiguity. If the request is
        underspecified, ask only the one most useful focused question.

        You do not write code yourself. Use tools when asked to inspect Daddy
        state or save/update an organized work item. Never claim that an agent
        was launched or messaged unless a dispatch was explicitly approved.
        Categories are bugs, uiux, future-features, concepts, and other.
        """
    }

    private static var orchestratorTools: [OllamaTool] {
        [
        OllamaTool(function: .init(
            name: "list_projects",
            description: "List projects Daddy can launch coding agents in.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([:]),
            ])
        )),
        OllamaTool(function: .init(
            name: "list_active_agents",
            description: "List coding agents currently running under Daddy.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([:]),
            ])
        )),
        OllamaTool(function: .init(
            name: "list_work_items",
            description: "List saved orchestrator work items, optionally filtered by category.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "category": .object([
                        "type": .string("string"),
                        "description": .string("bugs, uiux, future-features, concepts, or other"),
                    ])
                ]),
            ])
        )),
        OllamaTool(function: .init(
            name: "create_work_item",
            description: "Save a new organized idea or task as a Markdown work item.",
            parameters: .object([
                "type": .string("object"),
                "required": .array([.string("title"), .string("summary"), .string("category")]),
                "properties": .object([
                    "title": .object(["type": .string("string")]),
                    "summary": .object(["type": .string("string")]),
                    "raw_capture": .object(["type": .string("string")]),
                    "category": .object(["type": .string("string")]),
                    "priority": .object(["type": .string("string")]),
                    "project_id": .object(["type": .string("string")]),
                    "attachment_ids": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                    ]),
                ]),
            ])
        )),
        OllamaTool(function: .init(
            name: "update_work_item",
            description: "Update an existing Markdown work item after the user asks for a change.",
            parameters: .object([
                "type": .string("object"),
                "required": .array([.string("work_item_id")]),
                "properties": .object([
                    "work_item_id": .object(["type": .string("string")]),
                    "title": .object(["type": .string("string")]),
                    "summary": .object(["type": .string("string")]),
                    "category": .object(["type": .string("string")]),
                    "priority": .object(["type": .string("string")]),
                    "status": .object(["type": .string("string")]),
                ]),
            ])
        )),
        OllamaTool(function: .init(
            name: "request_agent_dispatch",
            description: "Prepare a work item to be sent to a coding agent. Daddy will ask the user for confirmation before acting.",
            parameters: .object([
                "type": .string("object"),
                "required": .array([.string("work_item_id"), .string("agent")]),
                "properties": .object([
                    "work_item_id": .object(["type": .string("string")]),
                    "agent": .object(["type": .string("string")]),
                    "project_id": .object(["type": .string("string")]),
                    "existing_session_id": .object(["type": .string("string")]),
                    "prompt": .object(["type": .string("string")]),
                ]),
            ])
        )),
        ]
    }

    func attachOrchestratorFile(_ url: URL) {
        do {
            let attachment = try OrchestratorAttachmentLoader.load(url)
            guard !orchestratorAttachments.contains(where: { $0.path == attachment.path }) else { return }
            orchestratorAttachments.append(attachment)
            pendingOrchestratorAttachmentIDs.append(attachment.id)
        } catch {
            orchestratorError = error.localizedDescription
        }
    }

    func removeOrchestratorAttachment(_ attachment: OrchestratorAttachment) {
        orchestratorAttachments.removeAll { $0.id == attachment.id }
        pendingOrchestratorAttachmentIDs.removeAll { $0 == attachment.id }
    }

    func switchOrchestratorCategory(to category: OrchestratorWorkCategory?) {
        guard category != orchestratorCategory, !orchestratorBusy else { return }

        let currentKey = orchestratorConversationKey(orchestratorCategory)
        orchestratorMessagesByCategory[currentKey] = orchestratorMessages
        orchestratorAttachmentsByCategory[currentKey] = orchestratorAttachments
        pendingOrchestratorAttachmentIDsByCategory[currentKey] = pendingOrchestratorAttachmentIDs

        orchestratorCategory = category
        let nextKey = orchestratorConversationKey(category)
        orchestratorMessages = orchestratorMessagesByCategory[nextKey] ?? []
        orchestratorAttachments = orchestratorAttachmentsByCategory[nextKey] ?? []
        pendingOrchestratorAttachmentIDs = pendingOrchestratorAttachmentIDsByCategory[nextKey] ?? []
        orchestratorStreamingText = ""
        orchestratorError = nil
        pendingOrchestratorDispatch = nil
    }

    func sendOrchestratorMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !orchestratorBusy else { return }

        let attachmentIDs = pendingOrchestratorAttachmentIDs
        orchestratorMessages.append(
            OrchestratorMessage(role: .user, content: trimmed, attachmentIDs: attachmentIDs)
        )
        pendingOrchestratorAttachmentIDs.removeAll()
        orchestratorStreamingText = ""
        orchestratorBusy = true
        orchestratorError = nil
        let turnID = UUID()
        orchestratorTurnID = turnID

        orchestratorTurnTask = Task { [weak self] in
            guard let self else { return }
            await self.runOrchestratorTurn(text: trimmed, turnID: turnID)
        }
    }

    func cancelOrchestratorTurn() {
        guard orchestratorBusy else { return }
        let partial = orchestratorStreamingText
        orchestratorTurnTask?.cancel()
        orchestratorTurnTask = nil
        orchestratorTurnID = nil
        orchestratorBusy = false
        orchestratorStreamingText = ""
        orchestratorError = nil
        if !partial.isEmpty {
            orchestratorMessages.append(
                OrchestratorMessage(role: .assistant, content: partial, wasStopped: true)
            )
        }
    }

    func clearOrchestratorConversation() {
        guard !orchestratorBusy else { return }
        resetOrchestratorConversation()
    }

    func resetOrchestratorConversation() {
        orchestratorMessages.removeAll()
        orchestratorAttachments.removeAll()
        pendingOrchestratorAttachmentIDs.removeAll()
        let key = orchestratorConversationKey(orchestratorCategory)
        orchestratorMessagesByCategory.removeValue(forKey: key)
        orchestratorAttachmentsByCategory.removeValue(forKey: key)
        pendingOrchestratorAttachmentIDsByCategory.removeValue(forKey: key)
        orchestratorStreamingText = ""
        orchestratorError = nil
        pendingOrchestratorDispatch = nil
    }

    func approveOrchestratorDispatch() {
        guard let pending = pendingOrchestratorDispatch,
              let project = project(pending.projectID) else { return }

        let target: MockAgent?
        if let existingID = pending.existingSessionID,
           let existing = agents.first(where: { $0.id == existingID && $0.isLive }) {
            target = existing
        } else {
            target = launchReal(pending.agent, in: project, workUnitID: workItem(pending.workItemID)?.id.uuidString)
        }

        guard let target else {
            orchestratorError = launchError ?? "Could not launch the requested agent"
            return
        }

        send(pending.prompt, to: target.id)
        if var item = workItem(pending.workItemID) {
            item.status = .dispatched
            item.linkedSessionIDs.append(target.id)
            item.updatedAt = Date()
            replaceWorkItem(item)
        }
        pendingOrchestratorDispatch = nil
        orchestratorMessages.append(
            OrchestratorMessage(
                role: .assistant,
                content: "Dispatched \(workItem(pending.workItemID)?.title ?? "the work item") to \(pending.agent.rawValue)."
            )
        )
    }

    func rejectOrchestratorDispatch() {
        guard pendingOrchestratorDispatch != nil else { return }
        pendingOrchestratorDispatch = nil
        orchestratorMessages.append(
            OrchestratorMessage(role: .assistant, content: "Dispatch cancelled. The work item remains saved.")
        )
    }

    func workItem(_ id: UUID) -> OrchestratorWorkItem? {
        orchestratorWorkItems.first { $0.id == id }
    }

    func replaceWorkItem(_ item: OrchestratorWorkItem) {
        guard let index = orchestratorWorkItems.firstIndex(where: { $0.id == item.id }) else { return }
        orchestratorWorkItems[index] = item
        orchestratorMarkdownStore.save(item)
    }

    func prepareOrchestratorDispatch(
        for item: OrchestratorWorkItem,
        agent: AgentKind,
        projectID: String?,
        existingSessionID: String?
    ) {
        let resolvedProjectID = projectID ?? item.projectID ?? selectedProjectID
        guard let resolvedProjectID, project(resolvedProjectID) != nil else {
            orchestratorError = "Choose a project before dispatching this work item"
            return
        }

        pendingOrchestratorDispatch = PendingOrchestratorDispatch(
            workItemID: item.id,
            agent: agent,
            projectID: resolvedProjectID,
            existingSessionID: existingSessionID,
            prompt: dispatchPrompt(for: item)
        )
    }

    private func runOrchestratorTurn(text: String, turnID: UUID) async {
        var messages: [OllamaMessage] = [
            OllamaMessage(role: .system, content: Self.orchestratorSystemPrompt)
        ]

        for message in orchestratorMessages where message.role == .user || message.role == .assistant {
            messages.append(
                OllamaMessage(
                    role: message.role == .user ? .user : .assistant,
                    content: messageContent(message),
                    images: imageData(for: message.attachmentIDs)
                )
            )
        }

        defer {
            if orchestratorTurnID == turnID {
                orchestratorBusy = false
                orchestratorStreamingText = ""
                orchestratorTurnTask = nil
                orchestratorTurnID = nil
            }
        }

        let tools = shouldUseOrchestratorTools(for: text) ? Self.orchestratorTools : []

        for _ in 0..<4 {
            var response: OllamaResponse?
            orchestratorStreamingText = ""

            do {
                for try await event in ollamaClient.chatStream(
                    model: orchestratorModel,
                    messages: messages,
                    tools: tools
                ) {
                    switch event {
                    case .text(let chunk):
                        guard !Task.isCancelled, orchestratorTurnID == turnID else { return }
                        orchestratorStreamingText += chunk
                    case .finished(let value):
                        guard !Task.isCancelled, orchestratorTurnID == turnID else { return }
                        response = value
                    }
                }
            } catch {
                guard !Task.isCancelled, orchestratorTurnID == turnID else { return }
                orchestratorError = error.localizedDescription
                return
            }

            guard !Task.isCancelled, orchestratorTurnID == turnID else { return }
            guard let response else {
                orchestratorError = "Ollama returned no response"
                return
            }

            messages.append(response.message)
            guard let calls = response.message.toolCalls, !calls.isEmpty else {
                if !orchestratorStreamingText.isEmpty {
                    orchestratorMessages.append(
                        OrchestratorMessage(role: .assistant, content: orchestratorStreamingText)
                    )
                }
                return
            }

            var approvalNeeded = false
            for call in calls {
                let result = executeOrchestratorTool(call)
                messages.append(
                    OllamaMessage(
                        role: .tool,
                        content: result.content,
                        toolName: call.function.name
                    )
                )
                if result.needsApproval { approvalNeeded = true }
            }

            if approvalNeeded {
                orchestratorMessages.append(
                    OrchestratorMessage(
                        role: .assistant,
                        content: "I prepared a dispatch request. Review it before I contact a coding agent."
                    )
                )
                return
            }
        }

        orchestratorError = "The orchestrator reached its tool-call limit for this turn"
    }

    private struct ToolResult {
        let content: String
        let needsApproval: Bool
    }

    private func executeOrchestratorTool(_ call: OllamaToolCall) -> ToolResult {
        let args = call.function.arguments

        switch call.function.name {
        case "list_projects":
            let projects = self.projects.map { "\($0.id): \($0.name) (\($0.path))" }
            return ToolResult(content: projects.isEmpty ? "No projects found." : projects.joined(separator: "\n"), needsApproval: false)

        case "list_active_agents":
            let active = agents.filter(\.isLive).map {
                "\($0.id): \($0.agent.rawValue) in project \($0.projectID), work \($0.workUnitID), state \(StateColors.name(for: $0.state))"
            }
            return ToolResult(content: active.isEmpty ? "No active agents." : active.joined(separator: "\n"), needsApproval: false)

        case "list_work_items":
            let category = args["category"].flatMap { $0.stringValue }.flatMap(normalizeCategory)
            let items = orchestratorWorkItems.filter { category == nil || $0.category == category }
            let output = items.map { "\($0.id.uuidString): [\($0.category.title)] \($0.title) (\($0.status.title))" }
            return ToolResult(content: output.isEmpty ? "No matching work items." : output.joined(separator: "\n"), needsApproval: false)

        case "create_work_item":
            guard let title = args["title"]?.stringValue,
                  let summary = args["summary"]?.stringValue,
                  let categoryValue = args["category"]?.stringValue,
                  let category = normalizeCategory(categoryValue) else {
                return ToolResult(content: "Missing or invalid title, summary, or category.", needsApproval: false)
            }

            let item = OrchestratorWorkItem(
                title: title,
                summary: summary,
                rawCapture: args["raw_capture"]?.stringValue ?? summary,
                category: category,
                priority: normalizePriority(args["priority"]?.stringValue),
                projectID: args["project_id"]?.stringValue,
                attachmentIDs: attachmentIDs(from: args["attachment_ids"])
                    ?? latestAttachmentIDs()
            )
            orchestratorWorkItems.insert(item, at: 0)
            selectedOrchestratorWorkItemID = item.id
            orchestratorMarkdownStore.save(item)
            return ToolResult(content: "Created work item \(item.id.uuidString): \(item.title)", needsApproval: false)

        case "update_work_item":
            guard let idValue = args["work_item_id"]?.stringValue,
                  let id = UUID(uuidString: idValue),
                  var item = workItem(id) else {
                return ToolResult(content: "Work item not found.", needsApproval: false)
            }
            if let value = args["title"]?.stringValue { item.title = value }
            if let value = args["summary"]?.stringValue { item.summary = value }
            if let value = args["category"]?.stringValue, let category = normalizeCategory(value) { item.category = category }
            if let value = args["priority"]?.stringValue { item.priority = normalizePriority(value) }
            if let value = args["status"]?.stringValue, let status = OrchestratorWorkStatus(rawValue: value) { item.status = status }
            item.updatedAt = Date()
            replaceWorkItem(item)
            return ToolResult(content: "Updated work item \(item.id.uuidString).", needsApproval: false)

        case "request_agent_dispatch":
            guard let idValue = args["work_item_id"]?.stringValue,
                  let id = UUID(uuidString: idValue),
                  let item = workItem(id),
                  let agentValue = args["agent"]?.stringValue,
                  let agent = AgentKind(rawValue: agentValue.lowercased()) else {
                return ToolResult(content: "Work item or coding agent not found.", needsApproval: false)
            }
            let projectID = args["project_id"]?.stringValue ?? item.projectID ?? selectedProjectID
            guard let projectID, project(projectID) != nil else {
                return ToolResult(content: "No valid project is associated with this work item.", needsApproval: false)
            }
            let prompt = args["prompt"]?.stringValue ?? dispatchPrompt(for: item)
            pendingOrchestratorDispatch = PendingOrchestratorDispatch(
                workItemID: item.id,
                agent: agent,
                projectID: projectID,
                existingSessionID: args["existing_session_id"]?.stringValue,
                prompt: prompt
            )
            return ToolResult(content: "Dispatch prepared and waiting for user approval.", needsApproval: true)

        default:
            return ToolResult(content: "Unknown tool: \(call.function.name)", needsApproval: false)
        }
    }

    private func imageData(for ids: [UUID]) -> [String]? {
        let values = ids.compactMap { id -> String? in
            guard let attachment = orchestratorAttachments.first(where: { $0.id == id }),
                  attachment.kind == .image,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: attachment.path)) else { return nil }
            return data.base64EncodedString()
        }
        return values.isEmpty ? nil : values
    }

    private func messageContent(_ message: OrchestratorMessage) -> String {
        let context = message.attachmentIDs.compactMap { id -> String? in
            guard let attachment = orchestratorAttachments.first(where: { $0.id == id }),
                  !attachment.extractedText.isEmpty else { return nil }
            return "\n\n--- Attached context: \(attachment.name) ---\n\(attachment.extractedText)\n--- End attached context ---"
        }
        return message.content + context.joined()
    }

    private func attachmentIDs(from value: JSONValue?) -> [UUID]? {
        guard case .array(let values) = value else { return nil }
        let ids = values.compactMap { $0.stringValue }.compactMap(UUID.init(uuidString:))
        return ids.isEmpty ? nil : ids
    }

    private func latestAttachmentIDs() -> [UUID] {
        orchestratorMessages.reversed().first(where: { !$0.attachmentIDs.isEmpty })?.attachmentIDs ?? []
    }

    private func orchestratorConversationKey(_ category: OrchestratorWorkCategory?) -> String {
        category?.rawValue ?? "all"
    }

    private func shouldUseOrchestratorTools(for text: String) -> Bool {
        let normalized = text.lowercased()
        let toolIntentTerms = [
            "organize", "work item", "work items", "create", "save", "update",
            "dispatch", "agent", "project", "active", "list"
        ]
        return toolIntentTerms.contains { normalized.contains($0) }
    }

    private func dispatchPrompt(for item: OrchestratorWorkItem) -> String {
        var prompt = "Work on this Daddy work item.\n\n"
        prompt += "# \(item.title)\n\n"
        prompt += "## Summary\n\(item.summary)\n\n"
        prompt += "## Original Capture\n\(item.rawCapture)\n"

        let attachments = item.attachmentIDs.compactMap { id in
            orchestratorAttachments.first { $0.id == id }
        }
        if !attachments.isEmpty {
            prompt += "\n## Attached Context\n"
            for attachment in attachments {
                prompt += "\n### \(attachment.name)\n"
                if attachment.extractedText.isEmpty {
                    prompt += "File: \(attachment.path)\n"
                } else {
                    prompt += attachment.extractedText + "\n"
                }
            }
        }
        return prompt
    }

    private func normalizeCategory(_ value: String) -> OrchestratorWorkCategory? {
        let normalized = value.lowercased().replacingOccurrences(of: "_", with: "-")
        if normalized.contains("bug") { return .bugs }
        if normalized.contains("ui") || normalized.contains("ux") || normalized.contains("design") { return .uiux }
        if normalized.contains("future") || normalized.contains("feature") { return .futureFeatures }
        if normalized.contains("concept") || normalized.contains("idea") { return .concepts }
        if normalized == "other" { return .other }
        return nil
    }

    private func normalizePriority(_ value: String?) -> OrchestratorPriority {
        guard let value, let priority = OrchestratorPriority(rawValue: value.lowercased()) else { return .medium }
        return priority
    }
}
