use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum PropertyValue {
    String(String),
    Number(f64),
    Boolean(bool),
    List(Vec<String>),
}

pub(crate) fn bom_prefix_len(content: &str) -> usize {
    content.len() - content.trim_start_matches('\u{feff}').len()
}

fn split(content: &str) -> (Option<&str>, &str) {
    let prefix = bom_prefix_len(content);
    let logical = &content[prefix..];
    let opening = prefix
        + if logical.starts_with("---\r\n") {
            5
        } else if logical.starts_with("---\n") {
            4
        } else {
            return (None, logical);
        };
    let mut cursor = opening;
    while cursor <= content.len() {
        let next = content[cursor..]
            .find('\n')
            .map(|offset| cursor + offset + 1)
            .unwrap_or(content.len());
        let end = if next == content.len() {
            content.len()
        } else {
            next - 1
        };
        let line = content[cursor..end].trim_end_matches('\r');
        if matches!(line.trim_end(), "---" | "...") {
            let body = if next < content.len() || content.ends_with('\n') {
                &content[next..]
            } else {
                ""
            };
            return (Some(&content[opening..cursor]), body);
        }
        if next >= content.len() {
            break;
        }
        cursor = next;
    }
    (None, logical)
}

pub(crate) fn unquote(value: &str) -> String {
    let value = value.trim();
    if value.len() >= 2 && value.starts_with('"') && value.ends_with('"') {
        serde_json::from_str(value).unwrap_or_else(|_| value[1..value.len() - 1].to_string())
    } else if value.len() >= 2 && value.starts_with('\'') && value.ends_with('\'') {
        value[1..value.len() - 1].to_string()
    } else {
        value.to_string()
    }
}

/// A hash starts a YAML comment only outside quoted scalar/list tokens.
pub(crate) fn without_comment(value: &str) -> &str {
    let mut quote = None;
    let mut escaped = false;
    let mut previous_whitespace = true;
    let mut token_start = true;
    let mut chars = value.char_indices().peekable();
    while let Some((index, character)) = chars.next() {
        if escaped {
            escaped = false;
        } else if let Some(current) = quote {
            if current == '"' && character == '\\' {
                escaped = true;
            } else if character == current {
                if current == '\'' && chars.peek().is_some_and(|(_, next)| *next == '\'') {
                    chars.next();
                } else {
                    quote = None;
                    token_start = false;
                }
            }
        } else if character == '#' && previous_whitespace {
            return value[..index].trim_end();
        } else if (character == '"' || character == '\'') && token_start {
            quote = Some(character);
        } else if character == '[' || character == ',' {
            token_start = true;
        } else if !character.is_whitespace() {
            token_start = false;
        }
        previous_whitespace = character.is_whitespace();
    }
    value.trim_end()
}

fn scalar(value: &str) -> PropertyValue {
    let value = value.trim();
    if value.eq_ignore_ascii_case("true") {
        PropertyValue::Boolean(true)
    } else if value.eq_ignore_ascii_case("false") {
        PropertyValue::Boolean(false)
    } else if let Ok(number) = value.parse::<f64>() {
        PropertyValue::Number(number)
    } else {
        PropertyValue::String(unquote(value))
    }
}

pub fn note_body(content: &str) -> &str {
    split(content).1
}

pub fn note_properties(content: &str) -> BTreeMap<String, PropertyValue> {
    let Some(raw) = split(content).0 else {
        return BTreeMap::new();
    };
    let lines: Vec<&str> = raw.lines().collect();
    let mut properties = BTreeMap::new();
    let mut index = 0;
    while index < lines.len() {
        let Some((raw_key, raw_value)) = lines[index].split_once(':') else {
            index += 1;
            continue;
        };
        let key = raw_key.trim();
        if key.is_empty() || raw_key.starts_with(char::is_whitespace) {
            index += 1;
            continue;
        }
        let value = without_comment(raw_value).trim();
        if value.is_empty() {
            let mut items = Vec::new();
            let mut cursor = index + 1;
            while cursor < lines.len() {
                let trimmed = lines[cursor].trim_start();
                let Some(item) = trimmed.strip_prefix("- ") else {
                    break;
                };
                items.push(unquote(without_comment(item)));
                cursor += 1;
            }
            if !items.is_empty() {
                properties.insert(key.to_string(), PropertyValue::List(items));
                index = cursor;
                continue;
            }
        } else if value.starts_with('[') && value.ends_with(']') {
            let items = value[1..value.len() - 1]
                .split(',')
                .map(unquote)
                .filter(|item| !item.is_empty())
                .collect();
            properties.insert(key.to_string(), PropertyValue::List(items));
            index += 1;
            continue;
        }
        properties.insert(key.to_string(), scalar(value));
        index += 1;
    }
    properties
}

pub fn note_title(content: &str, fallback: &str) -> String {
    note_body(content)
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .map(|line| line.trim_start_matches('#').trim())
        .filter(|line| !line.is_empty())
        .unwrap_or(fallback)
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_flat_properties_and_preserves_body() {
        let content =
            "---\nstatus: draft\npriority: 3\ntags:\n  - cli\n  - rust\n---\n# Note\n\nBody\n";
        let properties = note_properties(content);
        assert_eq!(properties["status"], PropertyValue::String("draft".into()));
        assert_eq!(properties["priority"], PropertyValue::Number(3.0));
        assert_eq!(
            properties["tags"],
            PropertyValue::List(vec!["cli".into(), "rust".into()])
        );
        assert_eq!(note_body(content), "# Note\n\nBody\n");
        assert_eq!(note_title(content, "Fallback"), "Note");
    }

    #[test]
    fn decodes_json_quoted_list_values_used_by_attachment_metadata() {
        let content =
            "---\nzerus-attachments:\n  - \"{\\\"id\\\":\\\"attachment-1\\\"}\"\n---\n# Note\n";
        let properties = note_properties(content);
        assert_eq!(
            properties["zerus-attachments"],
            PropertyValue::List(vec![r#"{"id":"attachment-1"}"#.into()])
        );
    }
}
