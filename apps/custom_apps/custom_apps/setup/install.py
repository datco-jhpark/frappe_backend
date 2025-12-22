import frappe

def after_install():
    """앱 설치 후 실행: All Item Groups 확인/생성, 기본 Item Group 삭제, 커스텀 Item Group 생성"""
    ensure_all_item_groups_exists()
    delete_default_item_groups()
    create_custom_item_groups()

def ensure_all_item_groups_exists():
    """All Item Groups가 없으면 생성"""
    if not frappe.db.exists("Item Group", "All Item Groups"):
        print("Creating root Item Group: All Item Groups")
        # NestedSet을 위한 기본 필드 설정
        doc = frappe.get_doc({
            "doctype": "Item Group",
            "item_group_name": "All Item Groups",
            "is_group": 1,
            "parent_item_group": "",
            "lft": 1,
            "rgt": 2
        })
        # NestedSet validation을 우회하기 위해 직접 DB에 insert
        frappe.db.sql("""
            INSERT INTO `tabItem Group` 
            (name, item_group_name, is_group, parent_item_group, lft, rgt, old_parent, docstatus, idx)
            VALUES ('All Item Groups', 'All Item Groups', 1, '', 1, 2, '', 0, 0)
        """)
        frappe.db.commit()
        print("Created root Item Group: All Item Groups")
    else:
        print("All Item Groups already exists")

def delete_default_item_groups():
    """ERPNext 기본 Item Group 삭제 (All Item Groups 제외)"""
    
    # ERPNext 기본 Item Groups
    default_groups = [
        "Products",
        "Raw Material", 
        "Services",
        "Sub Assemblies",
        "Consumable"
    ]
    
    for group_name in default_groups:
        if frappe.db.exists("Item Group", group_name):
            try:
                # 하위 항목이 있는지 확인
                children = frappe.db.count("Item Group", {"parent_item_group": group_name})
                if children == 0:
                    frappe.delete_doc("Item Group", group_name, 
                                      ignore_permissions=True, 
                                      force=True)
                    print(f"Deleted Item Group: {group_name}")
                else:
                    print(f"Cannot delete {group_name}: has child groups")
            except Exception as e:
                print(f"Error deleting {group_name}: {e}")
    
    frappe.db.commit()

def create_custom_item_groups():
    """7개의 커스텀 Item Group 생성"""
    
    custom_groups = [
        "상품",
        "원재료",
        "부재료",
        "제품",
        "반제품",
        "부산품",
        "저장품"
    ]
    
    # All Item Groups의 현재 rgt 값 가져오기
    root = frappe.db.get_value("Item Group", "All Item Groups", ["lft", "rgt"], as_dict=True)
    if not root:
        print("Error: All Item Groups not found")
        return
    
    current_rgt = root.rgt
    
    for idx, group_name in enumerate(custom_groups):
        # 이미 존재하는지 확인
        if not frappe.db.exists("Item Group", group_name):
            # NestedSet 값 계산
            lft = current_rgt
            rgt = current_rgt + 1
            
            # 직접 DB에 insert
            frappe.db.sql("""
                INSERT INTO `tabItem Group` 
                (name, item_group_name, is_group, parent_item_group, lft, rgt, old_parent, docstatus, idx)
                VALUES (%s, %s, 0, 'All Item Groups', %s, %s, '', 0, %s)
            """, (group_name, group_name, lft, rgt, idx + 1))
            
            current_rgt += 2
            print(f"Created Item Group: {group_name}")
        else:
            print(f"Item Group already exists: {group_name}")
    
    # All Item Groups의 rgt 값 업데이트
    frappe.db.sql("""
        UPDATE `tabItem Group` 
        SET rgt = %s 
        WHERE name = 'All Item Groups'
    """, (current_rgt,))
    
    frappe.db.commit()
    print(f"Updated All Item Groups rgt to {current_rgt}")
