app_name = "custom_apps"
app_title = "Custom Apps"
app_publisher = "Your Company"
app_description = "Custom Apps for Item Groups"
app_email = "admin@example.com"
app_license = "mit"

# Installation
# ------------
after_install = "custom_apps.setup.install.after_install"

# Fixtures
# --------
fixtures = [
    {
        "dt": "Item Group",
        "filters": [
            ["name", "not in", ["All Item Groups"]]
        ]
    }
]
