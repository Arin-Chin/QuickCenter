return {

  ["builtin_overrides"] = {

    ["fmcoversettings"] = {

      ["view"] = "common",
    },
    ["fontlist"] = {

      ["view"] = "common",
    },
    ["power"] = {

      ["view"] = "filemanager",
    },
    ["quit"] = {

      ["icon"] = "nerd:F08B",
      ["label"] = "退出",
      ["view"] = "common",
    },
    ["toggle_cloze_mode"] = {

      ["view"] = "common",
    },
  },
  ["custom"] = {

    ["custom_qa_1"] = {

      ["action_type"] = "plugin",
      ["icon"] = "nerd:F013",
      ["is_in_place"] = true,
      ["label"] = "Simple UI Setting",
      ["plugin_key"] = "simpleui",
      ["plugin_method"] = "__menu_callback",
      ["view"] = "filemanager",
    },
    ["custom_qa_10"] = {

      ["action_type"] = "dispatcher",
      ["dispatcher_action"] = "stats_sync",
      ["dispatcher_value"] = true,
      ["icon"] = "nerd:F021",
      ["is_in_place"] = true,
      ["label"] = "阅读统计：同步",
      ["view"] = "common",
    },
    ["custom_qa_11"] = {

      ["action_type"] = "dispatcher",
      ["dispatcher_action"] = "kosync_pull_progress",
      ["dispatcher_value"] = true,
      ["icon"] = "nerd:F404",
      ["is_in_place"] = true,
      ["label"] = "从其他设备拉取阅读进度",
      ["view"] = "reader",
    },
    ["custom_qa_2"] = {

      ["action_type"] = "dispatcher",
      ["dispatcher_action"] = "cloudstorage",
      ["dispatcher_value"] = true,
      ["icon"] = "nerd:E862",
      ["is_in_place"] = true,
      ["label"] = "云存储 +",
      ["view"] = "common",
    },
    ["custom_qa_6"] = {

      ["action_type"] = "dispatcher",
      ["dispatcher_action"] = "suspend",
      ["dispatcher_value"] = true,
      ["icon"] = "nerd:E3C9",
      ["is_in_place"] = true,
      ["label"] = "休眠",
      ["view"] = "common",
    },
    ["custom_qa_7"] = {

      ["action_type"] = "plugin",
      ["icon"] = "nerd:E81B",
      ["is_in_place"] = true,
      ["label"] = "系统统计",
      ["plugin_key"] = "systemstat",
      ["plugin_method"] = "__menu_callback",
      ["view"] = "common",
    },
    ["custom_qa_8"] = {

      ["action_type"] = "plugin",
      ["icon"] = "nerd:F455",
      ["is_in_place"] = true,
      ["label"] = "日历视图",
      ["plugin_key"] = "statistics",
      ["plugin_method"] = "submenu",
      ["plugin_path_indices"] = {

        [1] = 8,
      },
      ["view"] = "common",
    },
    ["custom_qa_9"] = {

      ["action_type"] = "menu",
      ["icon"] = "nerd:F25A",
      ["is_in_place"] = false,
      ["label"] = "手势管理",
      ["menu_path"] = {

        ["display_label"] = "手势管理",
        ["index_path"] = {

          [1] = 5,
          [2] = 1,
        },
        ["is_leaf"] = false,
        ["tab_index"] = 3,
        ["view"] = "filemanager",
      },
      ["view"] = "common",
    },
  },
  ["custom_list"] = {

    [1] = "custom_qa_1",
    [2] = "custom_qa_2",
    [3] = "custom_qa_6",
    [4] = "custom_qa_7",
    [5] = "custom_qa_8",
    [6] = "custom_qa_9",
    [7] = "custom_qa_10",
    [8] = "custom_qa_11",
  },
  ["default_config"] = {

    ["builtin_overrides"] = {

      ["fmcoversettings"] = {

        ["view"] = "common",
      },
      ["fontlist"] = {

        ["view"] = "common",
      },
      ["power"] = {

        ["view"] = "filemanager",
      },
      ["quit"] = {

        ["icon"] = "nerd:F08B",
        ["label"] = "退出",
        ["view"] = "common",
      },
      ["toggle_cloze_mode"] = {

        ["view"] = "common",
      },
    },
    ["custom"] = {

      ["custom_qa_1"] = {

        ["action_type"] = "plugin",
        ["icon"] = "nerd:F013",
        ["is_in_place"] = true,
        ["label"] = "Simple UI Setting",
        ["plugin_key"] = "simpleui",
        ["plugin_method"] = "__menu_callback",
        ["view"] = "filemanager",
      },
      ["custom_qa_10"] = {

        ["action_type"] = "dispatcher",
        ["dispatcher_action"] = "stats_sync",
        ["dispatcher_value"] = true,
        ["icon"] = "nerd:F021",
        ["is_in_place"] = true,
        ["label"] = "阅读统计：同步",
        ["view"] = "common",
      },
      ["custom_qa_2"] = {

        ["action_type"] = "dispatcher",
        ["dispatcher_action"] = "cloudstorage",
        ["dispatcher_value"] = true,
        ["icon"] = "nerd:E862",
        ["is_in_place"] = true,
        ["label"] = "云存储 +",
        ["view"] = "common",
      },
      ["custom_qa_5"] = {

        ["action_type"] = "dispatcher",
        ["dispatcher_action"] = "bookmarks",
        ["dispatcher_value"] = true,
        ["icon"] = "nerd:E7C2",
        ["is_in_place"] = true,
        ["label"] = "书签",
        ["view"] = "reader",
      },
      ["custom_qa_6"] = {

        ["action_type"] = "dispatcher",
        ["dispatcher_action"] = "suspend",
        ["dispatcher_value"] = true,
        ["icon"] = "nerd:E3C9",
        ["is_in_place"] = true,
        ["label"] = "休眠",
        ["view"] = "common",
      },
      ["custom_qa_7"] = {

        ["action_type"] = "plugin",
        ["icon"] = "nerd:E81B",
        ["is_in_place"] = true,
        ["label"] = "系统统计",
        ["plugin_key"] = "systemstat",
        ["plugin_method"] = "__menu_callback",
        ["view"] = "common",
      },
      ["custom_qa_8"] = {

        ["action_type"] = "plugin",
        ["icon"] = "nerd:F455",
        ["is_in_place"] = true,
        ["label"] = "日历视图",
        ["plugin_key"] = "statistics",
        ["plugin_method"] = "submenu",
        ["plugin_path_indices"] = {

          [1] = 8,
        },
        ["view"] = "common",
      },
      ["custom_qa_9"] = {

        ["action_type"] = "dispatcher",
        ["dispatcher_action"] = "open_gesture_manager",
        ["dispatcher_value"] = true,
        ["icon"] = "nerd:F25A",
        ["is_in_place"] = true,
        ["label"] = "打开手势管理",
        ["view"] = "common",
      },
    },
    ["custom_list"] = {

      [1] = "custom_qa_1",
      [2] = "custom_qa_2",
      [3] = "custom_qa_5",
      [4] = "custom_qa_6",
      [5] = "custom_qa_7",
      [6] = "custom_qa_8",
      [7] = "custom_qa_9",
      [8] = "custom_qa_10",
    },
    ["qa_auto_add_to_panel"] = false,
    ["qa_bg"] = "flat",
    ["qa_button_hold_edit"] = false,
    ["qa_button_size_pct"] = 100,
    ["qa_context_filter"] = true,
    ["qa_enabled"] = true,
    ["qa_filter_initialized"] = true,
    ["qa_frontlight"] = true,
    ["qa_icon_overrides"] = {

    },
    ["qa_label_scale_pct"] = 100,
    ["qa_labels"] = false,
    ["qa_settings_on_hold"] = false,
    ["qa_shape"] = "round",
    ["qa_shortcuts"] = {

      [1] = "custom_qa_2",
    },
    ["qa_slider_show_value"] = true,
    ["qa_slider_style"] = "line",
    ["qa_slots"] = {

      [1] = "wifi",
      [2] = "custom_qa_2",
      [3] = "custom_qa_10",
      [4] = "search",
      [5] = "reading_insights",
      [6] = "custom_qa_8",
      [7] = "screenshot",
      [8] = "custom_qa_5",
      [9] = "custom_qa_9",
      [10] = "custom_qa_7",
      [11] = "qa_settings",
      [12] = "custom_qa_1",
      [13] = "quit",
      [14] = "restart",
      [15] = "custom_qa_6",
    },
    ["qa_tab_icon"] = "quicksettings",
    ["qa_warmth"] = true,
    ["ui_font_overrides"] = {

    },
  },
  ["qa_auto_add_to_panel"] = false,
  ["qa_bg"] = "flat",
  ["qa_button_hold_edit"] = true,
  ["qa_button_size_pct"] = 100,
  ["qa_context_filter"] = true,
  ["qa_enabled"] = true,
  ["qa_filter_initialized"] = true,
  ["qa_frontlight"] = true,
  ["qa_icon_overrides"] = {

  },
  ["qa_label_scale_pct"] = 100,
  ["qa_labels"] = false,
  ["qa_layout_cols"] = 4,
  ["qa_layout_enabled"] = false,
  ["qa_layout_rows"] = 2,
  ["qa_settings_on_hold"] = false,
  ["qa_shape"] = "round",
  ["qa_shortcuts"] = {

    [1] = "screenshot",
  },
  ["qa_slider_show_value"] = true,
  ["qa_slider_style"] = "line",
  ["qa_slots"] = {

    [1] = "wifi",
    [2] = "custom_qa_2",
    [3] = "custom_qa_10",
    [4] = "custom_qa_11",
    [5] = "search",
    [6] = "reading_insights",
    [7] = "custom_qa_8",
    [8] = "screenshot",
    [9] = "custom_qa_9",
    [10] = "custom_qa_7",
    [11] = "qa_settings",
    [12] = "custom_qa_1",
    [13] = "quit",
    [14] = "restart",
    [15] = "custom_qa_6",
  },
  ["qa_tab_icon"] = "quicksettings",
  ["qa_warmth"] = true,
  ["saved_configs"] = {

    ["默认"] = {

      ["builtin_overrides"] = {

        ["fmcoversettings"] = {

          ["view"] = "common",
        },
        ["fontlist"] = {

          ["view"] = "common",
        },
        ["power"] = {

          ["view"] = "filemanager",
        },
        ["quit"] = {

          ["icon"] = "nerd:F08B",
          ["label"] = "退出",
          ["view"] = "common",
        },
        ["toggle_cloze_mode"] = {

          ["view"] = "common",
        },
      },
      ["custom"] = {

        ["custom_qa_1"] = {

          ["action_type"] = "plugin",
          ["icon"] = "nerd:F013",
          ["is_in_place"] = true,
          ["label"] = "Simple UI Setting",
          ["plugin_key"] = "simpleui",
          ["plugin_method"] = "__menu_callback",
          ["view"] = "filemanager",
        },
        ["custom_qa_10"] = {

          ["action_type"] = "dispatcher",
          ["dispatcher_action"] = "stats_sync",
          ["dispatcher_value"] = true,
          ["icon"] = "nerd:F021",
          ["is_in_place"] = true,
          ["label"] = "阅读统计：同步",
          ["view"] = "common",
        },
        ["custom_qa_11"] = {

          ["action_type"] = "dispatcher",
          ["dispatcher_action"] = "kosync_pull_progress",
          ["dispatcher_value"] = true,
          ["icon"] = "nerd:F404",
          ["is_in_place"] = true,
          ["label"] = "从其他设备拉取阅读进度",
          ["view"] = "reader",
        },
        ["custom_qa_2"] = {

          ["action_type"] = "dispatcher",
          ["dispatcher_action"] = "cloudstorage",
          ["dispatcher_value"] = true,
          ["icon"] = "nerd:E862",
          ["is_in_place"] = true,
          ["label"] = "云存储 +",
          ["view"] = "common",
        },
        ["custom_qa_6"] = {

          ["action_type"] = "dispatcher",
          ["dispatcher_action"] = "suspend",
          ["dispatcher_value"] = true,
          ["icon"] = "nerd:E3C9",
          ["is_in_place"] = true,
          ["label"] = "休眠",
          ["view"] = "common",
        },
        ["custom_qa_7"] = {

          ["action_type"] = "plugin",
          ["icon"] = "nerd:E81B",
          ["is_in_place"] = true,
          ["label"] = "系统统计",
          ["plugin_key"] = "systemstat",
          ["plugin_method"] = "__menu_callback",
          ["view"] = "common",
        },
        ["custom_qa_8"] = {

          ["action_type"] = "plugin",
          ["icon"] = "nerd:F455",
          ["is_in_place"] = true,
          ["label"] = "日历视图",
          ["plugin_key"] = "statistics",
          ["plugin_method"] = "submenu",
          ["plugin_path_indices"] = {

            [1] = 8,
          },
          ["view"] = "common",
        },
        ["custom_qa_9"] = {

          ["action_type"] = "menu",
          ["icon"] = "nerd:F25A",
          ["is_in_place"] = false,
          ["label"] = "手势管理",
          ["menu_path"] = {

            ["display_label"] = "手势管理",
            ["index_path"] = {

              [1] = 5,
              [2] = 1,
            },
            ["is_leaf"] = false,
            ["tab_index"] = 3,
            ["view"] = "filemanager",
          },
          ["view"] = "common",
        },
      },
      ["custom_list"] = {

        [1] = "custom_qa_1",
        [2] = "custom_qa_2",
        [3] = "custom_qa_6",
        [4] = "custom_qa_7",
        [5] = "custom_qa_8",
        [6] = "custom_qa_9",
        [7] = "custom_qa_10",
        [8] = "custom_qa_11",
      },
      ["qa_auto_add_to_panel"] = false,
      ["qa_bg"] = "flat",
      ["qa_button_hold_edit"] = true,
      ["qa_button_size_pct"] = 100,
      ["qa_context_filter"] = true,
      ["qa_enabled"] = true,
      ["qa_filter_initialized"] = true,
      ["qa_frontlight"] = true,
      ["qa_icon_overrides"] = {

      },
      ["qa_label_scale_pct"] = 100,
      ["qa_labels"] = false,
      ["qa_layout_cols"] = 4,
      ["qa_layout_enabled"] = false,
      ["qa_layout_rows"] = 2,
      ["qa_settings_on_hold"] = false,
      ["qa_shape"] = "round",
      ["qa_shortcuts"] = {

        [1] = "screenshot",
      },
      ["qa_slider_show_value"] = true,
      ["qa_slider_style"] = "line",
      ["qa_slots"] = {

        [1] = "wifi",
        [2] = "custom_qa_2",
        [3] = "custom_qa_10",
        [4] = "custom_qa_11",
        [5] = "search",
        [6] = "reading_insights",
        [7] = "custom_qa_8",
        [8] = "screenshot",
        [9] = "custom_qa_9",
        [10] = "custom_qa_7",
        [11] = "qa_settings",
        [12] = "custom_qa_1",
        [13] = "quit",
        [14] = "restart",
        [15] = "custom_qa_6",
      },
      ["qa_tab_icon"] = "quicksettings",
      ["qa_warmth"] = true,
      ["ui_font_overrides"] = {

      },
    },
  },
  ["ui_font_overrides"] = {

  },
  ["version"] = 1,
}