# Zellij KDL Layout Syntax

## Contents
- Structure
- Pane attributes
- Floating panes
- Tabs
- Templates

## Structure

```
layout {
    pane | tab | pane_template | tab_template | default_tab_template | new_tab_template
}
```

No `tab` nodes → entire content becomes `default_tab_template`.

## Pane Attributes

Child-braces for `args`, same-line otherwise:

| Attribute | Values | Notes |
|-----------|--------|-------|
| `split_direction` | `"horizontal"` / `"vertical"` | `"horizontal"` → stacked T/B; `"vertical"` → side-by-side L/R |
| `size` | `"50%"` / integer | Fixed or percentage space |
| `command` | path | Runs instead of shell |
| `args` | quoted strings | Child-braces: `{ args "-f" "/tmp/log" }` |
| `cwd` | path | Relative composes with parent |
| `focus` | `true` | First focused pane wins |
| `borderless` | `true` | Removes frame |
| `close_on_exit` | `true` | Closes when command exits |
| `start_suspended` | `true` | Waits for Enter |
| `stacked` | `true` | Children stack (one visible) |

```kdl
layout {
    pane command="htop"
    pane { command "htop"; args "-f" "/tmp/log" }
    pane { plugin location="zellij:status-bar" }
    pane { plugin location="file:/path/to/plugin.wasm" }
}
```

## Floating Panes

```kdl
floating_panes {
    pane { x 1 y "10%" width 200 height "50%" }
}
```

`x`, `y`, `width`, `height`: integer chars or quoted percentages.

## Tabs

```kdl
tab name="editor" focus=true split_direction="vertical" {
    pane; pane
}
tab name="logs" cwd="/var/log" {
    pane command="tail" { args "-f" "syslog" }
}
tab hide_floating_panes=true { pane; floating_panes { pane } }
```

Tab attributes: `name`, `split_direction`, `focus`, `cwd`, `hide_floating_panes`.

## Templates

```kdl
pane_template name="htop" command="htop"
pane_template name="stack" split_direction="vertical" {
    pane; children; pane  # insertion point
}
htop                            # use by bare name
stack { pane command="htop" }

tab_template name="with-bar" {
    pane borderless=true { plugin location="zellij:compact-bar" }
    children
}
with-bar name="tab 1" { pane }

default_tab_template { ... }    # all tabs
new_tab_template { ... }        # only runtime new tabs
```
