# RETRO_DESIGN.md

## Visual Style Reference
- Borland C++ 5.0
- Microsoft Visual C++ 6.0
- Windows 95/98 UI
- Turbo Pascal 7.0 (DOS-era IDE)

## Themes shipped
1. **VC++ 6.0** — gray panels on Windows XP Luna blue.
2. **Borland Delphi** — warm mustard-beige.
3. **Visual Basic 6.0** — deep navy desktop with gray panels.
4. **Turbo Pascal 7.0** — DOS navy desktop (#0000A8), gray 3D dialogs and a
   cyan (#00A8A8) menu highlight. The *editor surface stays light* (#fbfbf9,
   black text) because the syntax palette is shared by all four themes.

## Color Palette

| Name | Hex | Usage |
|------|-----|-------|
| Background | #C0C0C0 | Main window background |
| Panel | #D4D0C8 | Panel backgrounds |
| Border Dark | #404040 | Bottom/right borders |
| Border Light | #FFFFFF | Top/left borders |
| Highlight | #DFDFDF | Hover states |
| Shadow | #808080 | Disabled elements |
| Selection | #000080 | Selected items |
| Text | #000000 | All text |
| Error | #CC0000 | Error messages |

## 3D Button Effect

### Raised (normal):
- Top border: #FFFFFF
- Left border: #FFFFFF
- Bottom border: #404040
- Right border: #404040

### Pressed:
- Top border: #404040
- Left border: #404040
- Bottom border: #FFFFFF
- Right border: #FFFFFF

## Rules
- Corner radius: ALWAYS 0
- Border width: 2px for 3D effects
- Font: System default, size 12
- Code font: Monospace, size 14
- No animations (or minimal)
- No gradients
- No transparency
- Dense spacing (4-8px padding)