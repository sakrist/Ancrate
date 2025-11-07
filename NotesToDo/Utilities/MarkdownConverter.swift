//
//  MarkdownConverter.swift
//  NotesToDo
//
//  Created by Volodymyr Boichentsov on 05/11/2025.
//

import Foundation

/// Utility to convert Apple Notes protobuf data to Markdown format
class MarkdownConverter {
    
    /// Convert a Document to Markdown format
    static func convertToMarkdown(document: Document, title: String = "Untitled Note") -> String {
        if document.hasNote {
            let noteMarkdown = convertNoteToMarkdown(note: document.note)
            // Check if the note already starts with a title (heading)
            if noteMarkdown.hasPrefix("#") {
                return noteMarkdown
            } else {
                return "# \(title)\n\n\(noteMarkdown)"
            }
        } else {
            return "# \(title)\n\n"
        }
    }
    
    /// Convert an ANote to Markdown format
    static func convertToMarkdown(note: ANote) -> String {
        if let document = note.parsedDocument, document.hasNote {
            // Use protobuf data if available for richer formatting
            let noteMarkdown = convertNoteToMarkdown(note: document.note)
            // Check if the note already starts with a title (heading)
            if noteMarkdown.hasPrefix("#") {
                return noteMarkdown
            } else {
                return "# \(note.title)\n\n\(noteMarkdown)"
            }
        } else {
            // Fallback to plain text content
            return "# \(note.title)\n\n\(note.content)"
        }
    }
    
    /// Convert multiple notes to a single Markdown document
    static func convertToMarkdown(notes: [ANote]) -> String {
        var markdown = ""
        
        for (index, note) in notes.enumerated() {
            if index > 0 {
                markdown += "\n\n---\n\n"
            }
            markdown += convertToMarkdown(note: note)
        }
        
        return markdown
    }
    
    /// Convert a Note protobuf to Markdown
    private static func convertNoteToMarkdown(note: Note) -> String {
        var markdown = ""
        
        // Get the note text
        let noteText = note.hasNoteText ? note.noteText : ""
        
        // If there are attribute runs, process them for formatting
        if note.attributeRun.count > 0 {
            markdown += processAttributeRuns(noteText: noteText, attributeRuns: note.attributeRun)
        } else {
            // Fallback to plain note text
            markdown += noteText
        }
        
        return markdown
    }
    
    /// Process attribute runs to apply formatting to the note text
    private static func processAttributeRuns(noteText: String, attributeRuns: [AttributeRun]) -> String {
        var markdown = ""
        var currentOffset = 0
        
        // Group consecutive runs with similar formatting to avoid fragmented styling
        let groupedRuns = groupSimilarAttributeRuns(attributeRuns: attributeRuns)
        
        // Process grouped AttributeRuns sequentially to maintain order and formatting
        for runGroup in groupedRuns {
            let totalLength = runGroup.reduce(0) { $0 + Int($1.length) }
            let startIndex = currentOffset
            let endIndex = currentOffset + totalLength
            
            // Extract the text for this grouped run
            guard let text = extractTextForRun(noteText: noteText, startIndex: startIndex, endIndex: endIndex) else {
                currentOffset += totalLength
                continue
            }
            
            // Apply styling based on the AttributeRuns in the group
            let styledText = applyFormattingToRunGroup(runGroup: runGroup, text: text, currentOffset: currentOffset, markdown: markdown)
            
            markdown += styledText
            currentOffset += totalLength
        }
        
        return markdown
    }
    
    /// Extract text for a run group with bounds checking
    private static func extractTextForRun(noteText: String, startIndex: Int, endIndex: Int) -> String? {
        guard endIndex <= noteText.count else {
            return nil
        }
        
        let startIdx = noteText.index(noteText.startIndex, offsetBy: startIndex)
        let endIdx = noteText.index(noteText.startIndex, offsetBy: endIndex)
        return String(noteText[startIdx..<endIdx])
    }
    
    /// Apply formatting to a run group (paragraph styles or character styles)
    private static func applyFormattingToRunGroup(runGroup: [AttributeRun], text: String, currentOffset: Int, markdown: String) -> String {
        // Check for paragraph-level styling first
        if let styledText = applyParagraphFormattingIfPresent(runGroup: runGroup, text: text, currentOffset: currentOffset, markdown: markdown) {
            return styledText
        }
        
        // Apply character-level styling if no paragraph style was applied
        let firstRun = runGroup.first!
        return applyCharacterStyling(text: text, attributeRun: firstRun)
    }
    
    /// Apply paragraph-level formatting if any run in the group has paragraph styles
    private static func applyParagraphFormattingIfPresent(runGroup: [AttributeRun], text: String, currentOffset: Int, markdown: String) -> String? {
        for attributeRun in runGroup {
            if attributeRun.hasParagraphStyle {
                let paragraphStyle = attributeRun.paragraphStyle
                
                // Handle checklist items
                if let checklistText = handleChecklistFormatting(paragraphStyle: paragraphStyle, text: text, currentOffset: currentOffset, markdown: markdown) {
                    return checklistText
                }
                
                // Handle heading styles based on styleType
                if let headingText = handleHeadingAndListFormatting(paragraphStyle: paragraphStyle, text: text, currentOffset: currentOffset, markdown: markdown) {
                    return headingText
                }
                
                // Handle block quotes
                if let blockQuoteText = handleBlockQuoteFormatting(paragraphStyle: paragraphStyle, text: text, currentOffset: currentOffset, markdown: markdown) {
                    return blockQuoteText
                }
            }
        }
        return nil
    }
    
    /// Handle checklist formatting
    private static func handleChecklistFormatting(paragraphStyle: ParagraphStyle, text: String, currentOffset: Int, markdown: String) -> String? {
        guard paragraphStyle.hasChecklist else { return nil }
        
        let checklist = paragraphStyle.checklist
        let isCompleted = checklist.hasDone ? checklist.done != 0 : false
        
        // Check if this starts a new checklist item (at beginning of line)
        let isStartOfLine = text.hasPrefix("\n") || currentOffset == 0 || markdown.hasSuffix("\n")
        let hasNonWhitespaceContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        guard isStartOfLine && hasNonWhitespaceContent else { return nil }
        
        let checkbox = isCompleted ? "[x]" : "[ ]"
        
        if text.hasPrefix("\n") {
            // Remove the newline, add it back with checkbox
            let contentWithoutLeadingNewline = String(text.dropFirst())
            return "\n- \(checkbox) \(contentWithoutLeadingNewline)"
        } else {
            // At beginning or after newline, add checkbox
            return "- \(checkbox) \(text)"
        }
    }
    
    /// Handle heading and list formatting
    private static func handleHeadingAndListFormatting(paragraphStyle: ParagraphStyle, text: String, currentOffset: Int, markdown: String) -> String? {
        guard paragraphStyle.hasStyleType else { return nil }
        
        let styleType = paragraphStyle.styleType
        let isStartOfLine = text.hasPrefix("\n") || currentOffset == 0 || markdown.hasSuffix("\n")
        let hasNonWhitespaceContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        // For list items (styleType 100-203), be more lenient about positioning
        let isListItem = styleType >= 100 && styleType <= 203
        let shouldApplyStyle = isListItem ? hasNonWhitespaceContent : (isStartOfLine && hasNonWhitespaceContent)
        
        guard shouldApplyStyle else { return nil }
        
        if isListItem {
            // For list items, apply formatting to each line separately
            return applyListFormattingToEachLine(text: text, styleType: styleType, indentAmount: paragraphStyle.hasIndentAmount ? paragraphStyle.indentAmount : 0)
        } else {
            return applyParagraphStyle(text: text, styleType: styleType, indentAmount: paragraphStyle.hasIndentAmount ? paragraphStyle.indentAmount : 0)
        }
    }
    
    /// Handle block quote formatting
    private static func handleBlockQuoteFormatting(paragraphStyle: ParagraphStyle, text: String, currentOffset: Int, markdown: String) -> String? {
        guard paragraphStyle.hasBlockQuote && paragraphStyle.blockQuote > 0 else { return nil }
        
        let isStartOfLine = text.hasPrefix("\n") || currentOffset == 0 || markdown.hasSuffix("\n")
        let hasNonWhitespaceContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        guard isStartOfLine && hasNonWhitespaceContent else { return nil }
        
        if text.hasPrefix("\n") {
            let contentWithoutLeadingNewline = String(text.dropFirst())
            return "\n> \(contentWithoutLeadingNewline)"
        } else {
            return "> \(text)"
        }
    }
    
    /// Group consecutive AttributeRuns with similar formatting to prevent fragmented styling
    private static func groupSimilarAttributeRuns(attributeRuns: [AttributeRun]) -> [[AttributeRun]] {
        var groups: [[AttributeRun]] = []
        var currentGroup: [AttributeRun] = []
        
        for run in attributeRuns {
            if currentGroup.isEmpty {
                currentGroup.append(run)
            } else if haveSimilarFormatting(run1: currentGroup.last!, run2: run) {
                currentGroup.append(run)
            } else {
                // Start a new group
                groups.append(currentGroup)
                currentGroup = [run]
            }
        }
        
        // Add the last group
        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }
        
        return groups
    }
    
    /// Check if two AttributeRuns have similar character-level formatting
    private static func haveSimilarFormatting(run1: AttributeRun, run2: AttributeRun) -> Bool {
        // Don't group runs that have different paragraph styles
        if run1.hasParagraphStyle != run2.hasParagraphStyle {
            return false
        }
        
        if run1.hasParagraphStyle && run2.hasParagraphStyle {
            let ps1 = run1.paragraphStyle
            let ps2 = run2.paragraphStyle
            
            // Don't group if they have different paragraph-level formatting
            if ps1.hasChecklist != ps2.hasChecklist ||
               ps1.hasStyleType != ps2.hasStyleType ||
               ps1.hasBlockQuote != ps2.hasBlockQuote {
                return false
            }
            
            // If they both have the same paragraph style types, check if values match
            if ps1.hasChecklist && ps2.hasChecklist {
                // Different checklist items should not be grouped
                if ps1.checklist.uuid != ps2.checklist.uuid {
                    return false
                }
            }
            
            if ps1.hasStyleType && ps2.hasStyleType {
                if ps1.styleType != ps2.styleType {
                    return false
                }
            }
            
            if ps1.hasBlockQuote && ps2.hasBlockQuote {
                if ps1.blockQuote != ps2.blockQuote {
                    return false
                }
            }
        }
        
        // Check character-level formatting similarity
        return run1.hasFontWeight == run2.hasFontWeight &&
               run1.fontWeight == run2.fontWeight &&
               run1.hasEmphasisStyle == run2.hasEmphasisStyle &&
               run1.emphasisStyle == run2.emphasisStyle &&
               run1.hasUnderlined == run2.hasUnderlined &&
               run1.underlined == run2.underlined &&
               run1.hasStrikethrough == run2.hasStrikethrough &&
               run1.strikethrough == run2.strikethrough &&
               run1.hasSuperscript == run2.hasSuperscript &&
               run1.superscript == run2.superscript &&
               run1.hasLink == run2.hasLink &&
               run1.link == run2.link
    }
    
    /// Apply paragraph styles based on styleType (headings, block quotes, etc.)
    private static func applyParagraphStyle(text: String, styleType: Int32, indentAmount: Int32) -> String {
        let prefix: String
        let indent = String(repeating: "  ", count: max(0, Int(indentAmount)))
        
        // Map Apple Notes style types to markdown formatting
        switch styleType {
        // Heading styles
        case 0: prefix = "# "           // Title
        case 1: prefix = "## "          // Heading  
        case 2: prefix = "### "         // Subheading
        
        // Note: List styles (100-203) are handled by applyListFormattingToEachLine
        
        // Other potential paragraph styles
        default:
            prefix = ""
        }
        
        // Special-case: styleType 4 is inline code style — wrap in backticks
        if styleType == 4 {
            return applyCodeFormatting(text: text)
        }

        if !prefix.isEmpty {
            if text.hasPrefix("\n") {
                let contentWithoutLeadingNewline = String(text.dropFirst())
                return "\n\(prefix)\(contentWithoutLeadingNewline)"
            } else {
                return "\(prefix)\(text)"
            }
        }

        return text
    }
    
    /// Apply code formatting with proper handling of inline vs block code
    private static func applyCodeFormatting(text: String) -> String {
        // Check if it's multiline content
        let isMultiline = text.contains("\n")
        
        if isMultiline {
            // Use code block (```) for multiline content
            if text.hasPrefix("\n") {
                let contentWithoutLeadingNewline = String(text.dropFirst())
                if contentWithoutLeadingNewline.hasSuffix("\n") {
                    let contentWithoutTrailingNewline = String(contentWithoutLeadingNewline.dropLast())
                    return "\n```\n\(contentWithoutTrailingNewline)\n```\n"
                } else {
                    return "\n```\n\(contentWithoutLeadingNewline)\n```"
                }
            } else {
                if text.hasSuffix("\n") {
                    let contentWithoutTrailingNewline = String(text.dropLast())
                    return "```\n\(contentWithoutTrailingNewline)\n```\n"
                } else {
                    return "```\n\(text)\n```"
                }
            }
        } else {
            // Use inline code (`) for single line content
            if text.hasPrefix("\n") {
                let contentWithoutLeadingNewline = String(text.dropFirst())
                if contentWithoutLeadingNewline.hasSuffix("\n") {
                    let contentWithoutTrailingNewline = String(contentWithoutLeadingNewline.dropLast())
                    return "\n`\(contentWithoutTrailingNewline)`\n"
                } else {
                    return "\n`\(contentWithoutLeadingNewline)`"
                }
            } else {
                if text.hasSuffix("\n") {
                    let contentWithoutTrailingNewline = String(text.dropLast())
                    return "`\(contentWithoutTrailingNewline)`\n"
                } else {
                    return "`\(text)`"
                }
            }
        }
    }
    
    /// Apply list formatting to each line in the text separately
    private static func applyListFormattingToEachLine(text: String, styleType: Int32, indentAmount: Int32) -> String {
        let prefix: String
        let indent = String(repeating: "  ", count: max(0, Int(indentAmount)))
        
        // Map Apple Notes style types to markdown formatting
        switch styleType {
        // List styles (corrected based on Apple Notes actual behavior)
        case 100: prefix = "\(indent)- "     // Dash (was bullet in Apple Notes, but showing as dash)
        case 101: prefix = "\(indent)* "     // Bullet point (was dash in Apple Notes, but showing as bullet)
        case 102: prefix = "\(indent)1. "    // Numbered list (was plus in Apple Notes)
        case 103: prefix = "\(indent)- "     // Alternative dash
        
        // Additional numbered list styles
        case 200: prefix = "\(indent)1. "    // Numbered list
        case 201: prefix = "\(indent)1) "    // Numbered list with parenthesis
        case 202: prefix = "\(indent)a. "    // Alphabetic list
        case 203: prefix = "\(indent)i. "    // Roman numeral list
        
        // Other potential list styles
        default:
            // If styleType > 50, treat as some kind of list item with bullet
            if styleType > 50 {
                prefix = "\(indent)- "
            } else {
                prefix = ""
            }
        }
        
        guard !prefix.isEmpty else { return text }
        
        // Split the text by lines and apply list formatting to each non-empty line
        let lines = text.components(separatedBy: .newlines)
        var result: [String] = []
        
        for (_, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if !trimmedLine.isEmpty {
                // Apply list formatting to non-empty lines
                result.append("\(prefix)\(line)")
            } else {
                // Preserve empty lines for proper spacing between list groups
                result.append("")
            }
        }
        
        return result.joined(separator: "\n")
    }
    
    /// Apply character-level styling like bold, italic, underline, etc.
    private static func applyCharacterStyling(text: String, attributeRun: AttributeRun) -> String {
        var styledText = text
        
        // Skip styling for whitespace-only text to avoid unnecessary markup
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return text
        }
        
        // Only apply styling if this run contains actual content (not just punctuation or spaces)
        // This helps prevent fragmented styling like "**a****re**"
        let hasSignificantContent = trimmedText.count > 0 && !trimmedText.allSatisfy { $0.isPunctuation || $0.isWhitespace }
        
        if !hasSignificantContent {
            return text
        }
        
        // Apply link formatting first (wraps everything else)
        if attributeRun.hasLink && !attributeRun.link.isEmpty {
            styledText = "[\(styledText)](\(attributeRun.link))"
        }
        
        // Apply bold formatting (fontWeight > 0 indicates bold)
        if attributeRun.hasFontWeight && attributeRun.fontWeight > 0 {
            styledText = "**\(styledText)**"
        }
        
        // Apply italic formatting (emphasisStyle indicates italic)
        if attributeRun.hasEmphasisStyle && attributeRun.emphasisStyle > 0 {
            styledText = "*\(styledText)*"
        }
        
        // Apply strikethrough formatting
        if attributeRun.hasStrikethrough && attributeRun.strikethrough > 0 {
            styledText = "~~\(styledText)~~"
        }
        
        // Apply underline formatting (using HTML since markdown doesn't have native underline)
        if attributeRun.hasUnderlined && attributeRun.underlined > 0 {
            styledText = "<u>\(styledText)</u>"
        }
        
        // Apply superscript/subscript formatting
        if attributeRun.hasSuperscript && attributeRun.superscript != 0 {
            if attributeRun.superscript > 0 {
                styledText = "<sup>\(styledText)</sup>"
            } else {
                styledText = "<sub>\(styledText)</sub>"
            }
        }
        
        return styledText
    }
    
}
