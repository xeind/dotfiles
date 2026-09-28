# Nightingale for nushell. Colors from xeind/nightingale.nvim
# (lua/nightingale/colors.lua), mapped to the roles they play in nvim:
# strings green, functions blue, keywords purple, constants orange,
# types cyan, comments gray.

let c = {
  fg2: "#DCD7BA"  variable: "#e8e4ca"  gray: "#727169"  gray2: "#585858"
  selection: "#444444"  search: "#FF9E3B"
  blue: "#85a8da"  cyan: "#7cd0bf"  cyan2: "#9CABCA"  cyan3: "#A3D4D5"
  purple: "#a584c0"  purple2: "#957FB8"  purple3: "#D27E99"
  green: "#98BB6C"  yellow3: "#E6C384"  yellow6: "#f1c57e"
  orange: "#f5a284"  red: "#ff5353"  red3: "#FF5D62"
}

$env.config.highlight_resolved_externals = true

$env.config.color_config = ($env.config.color_config | merge {
  # values in tables and output
  separator: $c.gray2
  leading_trailing_space_bg: { attr: n }
  header: { fg: $c.yellow3 attr: b }
  row_index: $c.gray
  empty: $c.gray
  hints: $c.gray
  search_result: { fg: $c.search bg: $c.selection }
  bool: $c.orange
  int: $c.orange
  float: $c.orange
  filesize: $c.cyan2
  duration: $c.orange
  datetime: $c.purple3
  range: $c.yellow6
  string: $c.fg2
  nothing: $c.gray
  binary: $c.purple2
  cell-path: $c.variable
  record: $c.fg2
  list: $c.fg2
  closure: $c.blue
  glob: $c.cyan3

  # the command line as you type
  shape_internalcall: $c.blue
  shape_external: $c.red3
  shape_external_resolved: $c.blue
  shape_externalarg: $c.fg2
  shape_keyword: { fg: $c.purple attr: b }
  shape_flag: $c.purple2
  shape_string: $c.green
  shape_string_interpolation: $c.green
  shape_raw_string: $c.green
  shape_int: $c.orange
  shape_float: $c.orange
  shape_bool: $c.orange
  shape_nothing: $c.orange
  shape_datetime: $c.purple3
  shape_range: $c.yellow6
  shape_operator: $c.yellow6
  shape_pipe: $c.yellow6
  shape_redirection: $c.yellow6
  shape_and: $c.yellow6
  shape_or: $c.yellow6
  shape_variable: $c.variable
  shape_vardecl: $c.variable
  shape_signature: $c.cyan
  shape_record: $c.cyan
  shape_list: $c.cyan
  shape_table: $c.cyan
  shape_block: $c.blue
  shape_closure: $c.blue
  shape_filepath: $c.cyan3
  shape_directory: $c.cyan3
  shape_globpattern: $c.cyan3
  shape_literal: $c.orange
  shape_binary: $c.purple2
  shape_custom: $c.cyan
  shape_matching_brackets: { attr: u }
  shape_garbage: { fg: $c.red attr: b }
})

# completion and history menus
$env.config.menus = ($env.config.menus | each {|m|
  $m | upsert style {
    text: $c.fg2
    selected_text: { fg: $c.fg2 bg: $c.selection attr: b }
    description_text: $c.gray
    match_text: { attr: u }
    selected_match_text: { bg: $c.selection attr: bu }
  }
})

# fzf widgets (Ctrl+R, Ctrl+T, Alt+C): extras/fzf/nightingale.sh
$env.FZF_DEFAULT_OPTS = ([
  "--highlight-line" "--info=inline-right" "--ansi" "--layout=reverse" "--border=none"
  "--color=bg+:#444444,bg:#181616,border:#585858,fg:#C4B28A,gutter:#181616"
  "--color=header:#f5a284,hl+:#7ebcfd,hl:#7ebcfd,info:#909398,marker:#D27E99"
  "--color=pointer:#D27E99,prompt:#7ebcfd,query:#C4B28A:regular,scrollbar:#585858"
  "--color=separator:#f5a284,spinner:#D27E99"
] | str join " ")
