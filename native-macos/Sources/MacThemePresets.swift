import Foundation

/// The web and native Apple preset names and seven-role palettes. The approved
/// Mac default remains separate and is selected by clearing the custom palette.
enum MacThemePresets {
    static let all: [MacNamedTheme] = [
        .init(name: "Zerus", palette: .init(colors: [.accent: "#D84B40", .link: "#0B6ACD", .text: "#020817", .editorBg: "#FFFFFF", .surface: "#F9F8F6", .sidebarBg: "#1F1F23", .sidebarFg: "#E4E4E7"])),
        .init(name: "Ember", palette: .init(colors: [.accent: "#C2410C", .link: "#B45309", .text: "#292018", .editorBg: "#FFFCF7", .surface: "#F8F1E7", .sidebarBg: "#2C1C12", .sidebarFg: "#F0E4D7"])),
        .init(name: "Forest", palette: .init(colors: [.accent: "#2F9E63", .link: "#0F766E", .text: "#122117", .editorBg: "#FDFFFC", .surface: "#F1F6F0", .sidebarBg: "#14231A", .sidebarFg: "#D7E8DC"])),
        .init(name: "Ocean", palette: .init(colors: [.accent: "#0284C7", .link: "#2563EB", .text: "#0C1A26", .editorBg: "#FDFEFF", .surface: "#EFF4F8", .sidebarBg: "#0F1C2E", .sidebarFg: "#D5E2F0"])),
        .init(name: "Paper", palette: .init(colors: [.accent: "#D84B40", .link: "#2563EB", .text: "#1F2937", .editorBg: "#FFFFFF", .surface: "#F4F5F7", .sidebarBg: "#E9EBEF", .sidebarFg: "#27303F"])),
        .init(name: "Parchment", palette: .init(colors: [.accent: "#B85C38", .link: "#9A5B13", .text: "#32281F", .editorBg: "#FFFDF8", .surface: "#F6F0E4", .sidebarBg: "#EBE1D0", .sidebarFg: "#4A392A"])),
        .init(name: "Sage", palette: .init(colors: [.accent: "#2F855A", .link: "#0F766E", .text: "#21352B", .editorBg: "#FBFDF9", .surface: "#EEF4EB", .sidebarBg: "#DFEADD", .sidebarFg: "#294332"])),
        .init(name: "Lavender", palette: .init(colors: [.accent: "#7657D5", .link: "#6546C4", .text: "#2D2940", .editorBg: "#FEFCFF", .surface: "#F3F0F8", .sidebarBg: "#E7E1F1", .sidebarFg: "#403650"])),
        .init(name: "Midnight", palette: .init(colors: [.accent: "#E5484D", .link: "#6EA8FE", .text: "#DEE3EA", .editorBg: "#14171D", .surface: "#191D24", .sidebarBg: "#0E1116", .sidebarFg: "#CFD6DF"])),
        .init(name: "Nightshade", palette: .init(colors: [.accent: "#A78BFA", .link: "#8AB4F8", .text: "#E2DDF0", .editorBg: "#171522", .surface: "#1C1930", .sidebarBg: "#100E1A", .sidebarFg: "#D5CFE8"])),
        .init(name: "Cocoa", palette: .init(colors: [.accent: "#E0A458", .link: "#D08770", .text: "#ECE1D3", .editorBg: "#1F1A15", .surface: "#262019", .sidebarBg: "#171310", .sidebarFg: "#E6DCCC"])),
    ]
}
