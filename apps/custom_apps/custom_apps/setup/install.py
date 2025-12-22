import os

import frappe


def after_install():
	seed_item_groups()


def seed_item_groups(force: bool = False):
	force_env = os.environ.get("FORCE_SEED_ITEM_GROUPS")
	force = force or (force_env is not None and force_env not in {"0", "false", "False", "no", "NO"})
	_site_seed_item_groups(force=force)


def list_item_groups(parent: str = "All Item Groups"):
	if not frappe.db or not frappe.db.exists("Item Group", parent):
		return []
	return frappe.get_all(
		"Item Group",
		filters={"parent_item_group": parent},
		pluck="name",
	)


def _site_seed_item_groups(force: bool = False):
	if not frappe.db:
		return

	if not force and frappe.db.exists("DocType", "Item") and frappe.get_all("Item", limit=1):
		return

	root_group = "All Item Groups"
	if not frappe.db.exists("Item Group", root_group):
		return

	frappe.db.commit()
	_existing = list_item_groups(parent=root_group)

	for name in _existing:
		frappe.delete_doc("Item Group", name, force=1)

	groups = [
		"상품",
		"원재료",
		"부재료",
		"제품",
		"반제품",
		"부산품",
		"저장품",
	]

	for g in groups:
		if frappe.db.exists("Item Group", g):
			continue
		doc = frappe.get_doc(
			{
				"doctype": "Item Group",
				"item_group_name": g,
				"parent_item_group": root_group,
				"is_group": 1,
			}
		)
		doc.insert(ignore_permissions=True)

	frappe.db.commit()
