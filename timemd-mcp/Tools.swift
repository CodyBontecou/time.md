import Foundation

/// Declarative list of MCP tools exposed by timemd-mcp. Each entry is a raw
/// dictionary matching the shape required by the MCP `tools/list` response
/// (`name`, `description`, `inputSchema`).
enum Tools {
    static func all() -> [[String: Any]] {
        [
            tool(
                name: "get_schema",
                description: "Describe the time.md database schema: tables, columns, stream types, and available metadata values. Call this first to understand what queries are possible.",
                properties: [:],
                required: []
            ),
            tool(
                name: "get_range_totals",
                description: "Total screen time seconds grouped by stream_type (app_usage, web_usage, media_usage) for a date range.",
                properties: [
                    "since": .string("Date range specifier: '7d', '30d', 'today', 'yesterday', 'this_week', 'this_month', 'this_year', 'all', or ISO date 'yyyy-MM-dd'. Defaults to 7d."),
                    "until": .string("Optional end date (ISO 'yyyy-MM-dd'). Defaults to now.")
                ]
            ),
            tool(
                name: "get_today",
                description: "Today's total screen time plus top apps and per-stream breakdown.",
                properties: [
                    "limit": .integer("Max number of top apps to return (default 20).")
                ]
            ),
            tool(
                name: "get_top_apps",
                description: "Top apps by total duration for a date range. Returns app_name, total_seconds, session_count.",
                properties: [
                    "since": .string("Range specifier. Default 7d."),
                    "until": .string("Optional end date."),
                    "limit": .integer("Max number of apps (default 25, max 500)."),
                    "stream_type": .string("Optional filter: app_usage | web_usage | media_usage.")
                ]
            ),
            tool(
                name: "get_top_categories",
                description: "Top user-defined categories by total duration. Joins usage with app_category_map (uncategorized apps are bucketed as 'Uncategorized').",
                properties: [
                    "since": .string("Range specifier. Default 7d."),
                    "until": .string("Optional end date."),
                    "limit": .integer("Max categories (default 20).")
                ]
            ),
            tool(
                name: "get_sessions",
                description: "Raw session rows for a date range, optionally filtered by app name or stream type. Returns non-aggregated records.",
                properties: [
                    "since": .string("Range specifier. Default 1d."),
                    "until": .string("Optional end date."),
                    "app_name": .string("Optional: filter to a single app. Accepts bundle IDs or human-readable names (e.g. 'World of Warcraft', 'Slack'). Resolved via fuzzy match if no exact bundle ID exists."),
                    "stream_type": .string("Optional: app_usage | web_usage | media_usage."),
                    "limit": .integer("Max rows (default 500, max 10000).")
                ]
            ),
            tool(
                name: "get_hourly_distribution",
                description: "Screen time grouped by hour of day (0-23) across a date range. Useful for peak-hour analysis.",
                properties: [
                    "since": .string("Range specifier. Default 7d."),
                    "until": .string("Optional end date."),
                    "app_name": .string("Optional: restrict to a single app.")
                ]
            ),
            tool(
                name: "get_daily_trend",
                description: "Per-day totals across a date range. Returns one row per calendar day.",
                properties: [
                    "since": .string("Range specifier. Default 30d."),
                    "until": .string("Optional end date."),
                    "app_name": .string("Optional: restrict to a single app.")
                ]
            ),
            tool(
                name: "get_weekday_breakdown",
                description: "Average seconds per weekday (0=Sunday..6=Saturday) over a date range, plus number of days observed.",
                properties: [
                    "since": .string("Range specifier. Default 30d."),
                    "until": .string("Optional end date.")
                ]
            ),
            tool(
                name: "get_app_detail",
                description: "Deep dive on a single app: total seconds, session count, daily trend, hourly distribution, longest sessions, and category.",
                properties: [
                    "app_name": .string("Required. App name to look up — bundle ID or human-readable name (e.g. 'World of Warcraft', 'Slack'). Resolved via fuzzy match if needed."),
                    "since": .string("Range specifier. Default 30d."),
                    "until": .string("Optional end date.")
                ],
                required: ["app_name"]
            ),
            tool(
                name: "get_web_usage",
                description: "Web browsing activity (stream_type = 'web_usage') aggregated by app/domain for a date range.",
                properties: [
                    "since": .string("Range specifier. Default 7d."),
                    "until": .string("Optional end date."),
                    "limit": .integer("Max rows (default 50).")
                ]
            ),
            tool(
                name: "get_media_usage",
                description: "Media consumption activity (stream_type = 'media_usage') aggregated by app for a date range.",
                properties: [
                    "since": .string("Range specifier. Default 7d."),
                    "until": .string("Optional end date."),
                    "limit": .integer("Max rows (default 50).")
                ]
            ),
            tool(
                name: "get_longest_sessions",
                description: "Top N longest individual sessions across a date range.",
                properties: [
                    "since": .string("Range specifier. Default 30d."),
                    "until": .string("Optional end date."),
                    "limit": .integer("Default 20."),
                    "stream_type": .string("Optional filter.")
                ]
            ),
            tool(
                name: "get_session_buckets",
                description: "Distribution of sessions across duration buckets (<1m, 1-5m, 5-15m, 15-30m, 30-60m, 60m+).",
                properties: [
                    "since": .string("Range specifier. Default 7d."),
                    "until": .string("Optional end date.")
                ]
            ),
            tool(
                name: "get_focus_blocks",
                description: "Sessions at or above a minimum duration threshold, grouped by day. Default threshold is 15 minutes.",
                properties: [
                    "since": .string("Range specifier. Default 7d."),
                    "until": .string("Optional end date."),
                    "min_duration_seconds": .number("Minimum session length in seconds (default 900 = 15m).")
                ]
            ),
            tool(
                name: "get_context_switches",
                description: "Number of app_usage sessions per day — a proxy for context-switch count.",
                properties: [
                    "since": .string("Range specifier. Default 7d."),
                    "until": .string("Optional end date.")
                ]
            ),
            tool(
                name: "get_app_transitions",
                description: "Most common app-to-app transitions (from_app → to_app) using a SQL window function over ordered sessions.",
                properties: [
                    "since": .string("Range specifier. Default 7d."),
                    "until": .string("Optional end date."),
                    "limit": .integer("Max transitions (default 25).")
                ]
            ),
            tool(
                name: "get_devices",
                description: "Distinct device_ids seen in the usage table with session counts and first/last-seen timestamps.",
                properties: [:]
            ),
            tool(
                name: "get_stream_types",
                description: "Distinct stream_types present in the database with their total session counts and seconds.",
                properties: [:]
            ),
            tool(
                name: "get_category_mappings",
                description: "All app → category mappings stored in category-mappings.db.",
                properties: [:]
            ),
            tool(
                name: "compare_periods",
                description: "Compare two date ranges and return totals plus per-app deltas. Useful for 'this week vs last week' style questions.",
                properties: [
                    "current_since": .string("Current range start specifier (e.g. '7d')."),
                    "current_until": .string("Optional current range end."),
                    "previous_since": .string("Previous range start specifier."),
                    "previous_until": .string("Optional previous range end."),
                    "limit": .integer("Max app deltas returned (default 25).")
                ]
            ),
            tool(
                name: "get_heatmap",
                description: "Weekday × hour 2D heatmap of screen time. Returns one row per (weekday, hour) pair. Weekday 0=Sunday..6=Saturday.",
                properties: [
                    "since": .string("Range specifier. Default 30d."),
                    "until": .string("Optional end date."),
                    "app_name": .string("Optional: restrict to a single app."),
                    "stream_type": .string("Optional: app_usage | web_usage | media_usage.")
                ]
            ),
            tool(
                name: "get_daily_app_breakdown",
                description: "For each day in a range, the top N apps ranked by duration. One row per (day, app) pair.",
                properties: [
                    "since": .string("Range specifier. Default 7d."),
                    "until": .string("Optional end date."),
                    "top_per_day": .integer("Max apps per day (default 5, max 50).")
                ]
            ),
            tool(
                name: "get_category_trend",
                description: "Per-day totals grouped by category. Joins usage with app_category_map. Uncategorized apps bucket as 'Uncategorized'.",
                properties: [
                    "since": .string("Range specifier. Default 30d."),
                    "until": .string("Optional end date.")
                ]
            ),
            tool(
                name: "get_first_last_use",
                description: "For each day in a range: earliest session start and latest session start. Useful for 'when did I start/stop working' questions.",
                properties: [
                    "since": .string("Range specifier. Default 30d."),
                    "until": .string("Optional end date."),
                    "stream_type": .string("Optional: filter by stream_type. Defaults to app_usage.")
                ]
            ),
            tool(
                name: "get_active_days",
                description: "Days in a range with any recorded activity, plus zero-day gaps (calendar days in the range with nothing tracked).",
                properties: [
                    "since": .string("Range specifier. Default 30d."),
                    "until": .string("Optional end date.")
                ]
            ),
            tool(
                name: "get_time_of_day_split",
                description: "Screen time bucketed into time-of-day periods: night (<6), morning (6-11), afternoon (12-16), evening (17-20), late_night (21-23).",
                properties: [
                    "since": .string("Range specifier. Default 7d."),
                    "until": .string("Optional end date.")
                ]
            ),
            tool(
                name: "get_weekend_vs_weekday",
                description: "Compare weekend (Sat/Sun) vs weekday totals and averages per day.",
                properties: [
                    "since": .string("Range specifier. Default 30d."),
                    "until": .string("Optional end date.")
                ]
            ),
            tool(
                name: "get_new_apps",
                description: "Apps whose earliest session in the entire history falls within the specified range — i.e. apps making their debut.",
                properties: [
                    "since": .string("Range specifier. Default 30d."),
                    "until": .string("Optional end date."),
                    "limit": .integer("Max apps (default 25).")
                ]
            ),
            tool(
                name: "get_abandoned_apps",
                description: "Apps used in the previous period but not in the current period. Current and previous are two adjacent equal-length ranges.",
                properties: [
                    "current_since": .string("Current range start specifier. Default 7d."),
                    "current_until": .string("Optional current range end."),
                    "previous_since": .string("Previous range start specifier. Default 14d."),
                    "previous_until": .string("Optional previous range end (defaults to current_since)."),
                    "limit": .integer("Max apps returned (default 25).")
                ]
            ),
            tool(
                name: "get_usage_streaks",
                description: "Longest consecutive-day streaks of activity in a range, computed via gaps-and-islands.",
                properties: [
                    "since": .string("Range specifier. Default all."),
                    "until": .string("Optional end date."),
                    "limit": .integer("Max streaks returned (default 10).")
                ]
            ),
            tool(
                name: "get_pickup_count",
                description: "Number of 'pickup' sessions — app_usage sessions shorter than a threshold (default 10s). A proxy for phone-unlock / quick-glance behaviour.",
                properties: [
                    "since": .string("Range specifier. Default 7d."),
                    "until": .string("Optional end date."),
                    "threshold_seconds": .number("Max duration to count as a pickup (default 10).")
                ]
            ),
            tool(
                name: "get_typical_day",
                description: "Average hourly distribution across a range: for each hour 0..23, the mean seconds across observed days.",
                properties: [
                    "since": .string("Range specifier. Default 30d."),
                    "until": .string("Optional end date."),
                    "app_name": .string("Optional: restrict to a single app.")
                ]
            ),
            tool(
                name: "get_metadata_hash_breakdown",
                description: "Distinct metadata_hash values with session counts and totals. Useful for checking how much data comes from 'direct_observation' (in-app tracker) vs knowledgeC fallback.",
                properties: [
                    "since": .string("Range specifier. Default all."),
                    "until": .string("Optional end date.")
                ]
            ),
            tool(
                name: "raw_query",
                description: "Run a read-only SQL SELECT against screentime.db. The category-mappings database is ATTACHed as 'cat' (cat.app_category_map). Only SELECT/WITH/EXPLAIN is permitted and only a single statement. Use get_schema first to see columns.",
                properties: [
                    "sql": .string("SQL SELECT statement. No semicolons allowed.")
                ],
                required: ["sql"]
            )
        ]
    }

    // MARK: - Schema builder

    enum Prop {
        case string(String)
        case integer(String)
        case number(String)

        var dict: [String: Any] {
            switch self {
            case .string(let desc):
                return ["type": "string", "description": desc]
            case .integer(let desc):
                return ["type": "integer", "description": desc]
            case .number(let desc):
                return ["type": "number", "description": desc]
            }
        }
    }

    private static func tool(
        name: String,
        description: String,
        properties: [String: Prop],
        required: [String] = []
    ) -> [String: Any] {
        var schema: [String: Any] = [
            "type": "object",
            "properties": properties.mapValues { $0.dict }
        ]
        if !required.isEmpty {
            schema["required"] = required
        }
        return [
            "name": name,
            "description": description,
            "inputSchema": schema
        ]
    }
}
