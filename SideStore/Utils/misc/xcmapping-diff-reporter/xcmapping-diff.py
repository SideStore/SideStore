#!/usr/bin/env python3
"""
Usage:
    python xml_diff.py old.xml new.xml

This script recursively compares two XML files and captures differences using
a “node path” notation. It categorizes errors into types such as "mismatch",
"missing node", and "extra node". For mismatches, the category is set to 
"mismatching in old.xml and new.xml". At the end, the script prints all errors 
grouped by error type.

For repeated nodes (for example, <object> elements), a specialized key is computed
(ignoring internal idrefs) so that the report uses a human‐friendly description.
It also ignores comparing any attribute named "sourcemodeldata" (or "destinationmodeldata").
"""
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict

# Constants for ignore lists, categories, and error types
IGNORED_ATTRIBUTES = {"sourcemodeldata", "destinationmodeldata", "id", "idrefs", "mappingnumber"}
CATEGORY_EXTRA = "extra in new.xml"
CATEGORY_MISSING = "missing in new.xml while present in old.xml"
CATEGORY_MISMATCH = "mismatching in old.xml and new.xml"
TYPE_MISMATCH = "mismatch"
TYPE_MISSING = "missing node"
TYPE_EXTRA = "extra node"


def append_diff(diffs, diff_type, diff_info):
    """
    Central method to add a difference to the diffs list.
    This allows setting a single breakpoint to catch all diff additions.
    """
    diffs.append((diff_type, diff_info))
    # You can add a breakpoint here to inspect all diffs as they're recorded
    return diffs


def get_object_key(elem):
    """Create a unique key for an <object> node based on its type and attributes."""
    typ = elem.get("type")
    
    if typ == "XDDEVENTITYMAPPING":
        return create_event_entity_mapping_key(elem)
    elif typ in ("XDDEVATTRIBUTEMAPPING", "XDDEVRELATIONSHIPMAPPING"):
        return create_attribute_or_relationship_mapping_key(elem)
    elif typ == "XDDEVMAPPINGMODEL":
        return create_mapping_model_key(elem)
    
    return (elem.tag,)


def create_event_entity_mapping_key(elem):
    """Create a key for XDDEVENTITYMAPPING objects."""
    sourcename = elem.find("attribute[@name='sourcename']")
    destinationname = elem.find("attribute[@name='destinationname']")
    mappingtypename = elem.find("attribute[@name='mappingtypename']")
    
    return (
        "XDDEVENTITYMAPPING",
        sourcename.text.strip() if sourcename is not None else "",
        destinationname.text.strip() if destinationname is not None else "",
        mappingtypename.text.strip() if mappingtypename is not None else "",
    )


def create_attribute_or_relationship_mapping_key(elem):
    """Create a key for XDDEVATTRIBUTEMAPPING or XDDEVRELATIONSHIPMAPPING objects."""
    name_elem = elem.find("attribute[@name='name']")
    name_val = name_elem.text.strip() if name_elem is not None else ""
    return (elem.get("type"), name_val)


def create_mapping_model_key(elem):
    """Create a key for XDDEVMAPPINGMODEL objects."""
    sourcemodelpath = elem.find("attribute[@name='sourcemodelpath']")
    path_val = sourcemodelpath.text.strip() if sourcemodelpath is not None else ""
    return ("XDDEVMAPPINGMODEL", path_val)


def format_object_key(key):
    """Format an object key into a human-readable string."""
    if key[0] == "XDDEVENTITYMAPPING":
        return f"destination name: {key[2]}, mappingTypename: {key[3]}"
    elif key[0] in ("XDDEVATTRIBUTEMAPPING", "XDDEVRELATIONSHIPMAPPING"):
        return f"name: {key[1]}"
    elif key[0] == "XDDEVMAPPINGMODEL":
        return f"sourcemodelpath: {key[1]}"
    
    return str(key)


def format_element(elem):
    """Format an element as a human-readable string."""
    if elem.tag == "object":
        typ = elem.get("type")
        if typ == "XDDEVENTITYMAPPING":
            return format_event_entity_mapping(elem)
        
        key = get_object_key(elem)
        return f"[{format_object_key(key)}]"
    
    text = (elem.text or "").strip()
    return f"{elem.tag}: '{text}'" if text else elem.tag


def format_event_entity_mapping(elem):
    """Format an XDDEVENTITYMAPPING element."""
    dest = elem.find("attribute[@name='destinationname']")
    mappingtypename = elem.find("attribute[@name='mappingtypename']")
    dest_val = dest.text.strip() if dest is not None else ""
    mappingtypename_val = mappingtypename.text.strip() if mappingtypename is not None else ""
    return f"{{ destination name: {dest_val}, mappingTypename: {mappingtypename_val} }}"


def get_element_value(elem):
    """Get the text value of an element if it has no children."""
    return (elem.text or "").strip() if len(list(elem)) == 0 else ""


def check_missing_nodes(old_elem, new_elem, path):
    """Check for missing or extra nodes between old and new XML."""
    diffs = []
    
    if old_elem is None and new_elem is None:
        return diffs, False
    
    # Handle extra node (in new but not in old)
    if old_elem is None:
        formatted_elem = format_element(new_elem)
        value = get_element_value(new_elem)
        diff_info = {
            "category": CATEGORY_EXTRA, 
            "path": path, 
            "new": formatted_elem
        }
        if value:
            diff_info["value"] = value
        append_diff(diffs, TYPE_EXTRA, diff_info)
        return diffs, False
    
    # Handle missing node (in old but not in new)
    if new_elem is None:
        formatted_elem = format_element(old_elem)
        value = get_element_value(old_elem)
        diff_info = {
            "category": CATEGORY_MISSING, 
            "path": path, 
            "old": formatted_elem
        }
        if value:
            diff_info["value"] = value
        append_diff(diffs, TYPE_MISSING, diff_info)
        return diffs, False
    
    return diffs, True


def compare_tags(old_elem, new_elem, path):
    """Compare tags of two elements."""
    diffs = []
    if old_elem.tag != new_elem.tag:
        diff_info = {
            "category": CATEGORY_MISMATCH,
            "path": f"{path} tag",
            "old": old_elem.tag,
            "new": new_elem.tag,
            "type": "tag"
        }
        append_diff(diffs, TYPE_MISMATCH, diff_info)
    return diffs


def compare_text(old_elem, new_elem, path):
    """Compare text content of two elements."""
    diffs = []
    
    # Skip comparisons for mappingnumber attributes
    if old_elem.tag == "attribute" and old_elem.get("name") == "mappingnumber":
        return diffs
        
    text_old = (old_elem.text or "").strip()
    text_new = (new_elem.text or "").strip()
    
    if text_old != text_new:
        diff_info = {
            "category": CATEGORY_MISMATCH,
            "path": f"{path} text",
            "old": text_old,
            "new": text_new,
            "type": "text"
        }
        append_diff(diffs, TYPE_MISMATCH, diff_info)
    return diffs


def compare_attributes(old_elem, new_elem, path):
    """Compare attributes of two elements, ignoring specified attributes."""
    diffs = []
    all_attrs = set(old_elem.attrib.keys()).union(new_elem.attrib.keys())
    
    for attr in [x for x in all_attrs if x not in IGNORED_ATTRIBUTES]:
        val_old = old_elem.attrib.get(attr)
        val_new = new_elem.attrib.get(attr)
        
        if val_old != val_new:
            diff_info = {
                "category": CATEGORY_MISMATCH,
                "path": f"{path} attribute '{attr}'",
                "old": val_old,
                "new": val_new,
                "type": "attribute"
            }
            append_diff(diffs, TYPE_MISMATCH, diff_info)
    return diffs


def handle_plist_keys(old_list, new_list, path, tag):
    """Handle special comparison for <key> elements in a plist dict."""
    diffs = []
    old_keys = [(child.text or "").strip() for child in old_list]
    new_keys = [(child.text or "").strip() for child in new_list]
    
    if set(old_keys) == set(new_keys):
        return diffs

    missing = [k for k in old_keys if k not in new_keys]
    extra = [k for k in new_keys if k not in old_keys]
    
    # Handle case where exactly one key is changed
    if len(missing) == 1 and len(extra) == 1:
        index = old_keys.index(missing[0])
        subpath = f"{path}.{tag}[{index}]"
        diff_info = {
            "category": CATEGORY_MISMATCH,
            "path": f"{subpath} text",
            "old": missing[0],
            "new": extra[0],
            "type": "text"
        }
        append_diff(diffs, TYPE_MISMATCH, diff_info)
    else:
        # Handle missing keys
        for k in missing:
            index = old_keys.index(k)
            subpath = f"{path}.{tag}[{index}]"
            diff_info = {
                "category": CATEGORY_MISSING,
                "path": f"{subpath} text",
                "old": k,
                "value": k
            }
            append_diff(diffs, TYPE_MISSING, diff_info)
        
        # Handle extra keys
        for k in extra:
            index = new_keys.index(k)
            subpath = f"{path}.{tag}[{index}]"
            diff_info = {
                "category": CATEGORY_EXTRA,
                "path": f"{subpath} text",
                "new": k,
                "value": k
            }
            append_diff(diffs, TYPE_EXTRA, diff_info)
    
    return diffs


def handle_object_nodes(old_list, new_list, path):
    """Compare <object> nodes by their computed key."""
    diffs = []
    dict_old = {get_object_key(child): child for child in old_list}
    dict_new = {get_object_key(child): child for child in new_list}
    
    for key in set(dict_old.keys()).union(dict_new.keys()):
        subpath = f"{path}.object[{format_object_key(key)}]"
        child_old = dict_old.get(key)
        child_new = dict_new.get(key)
        
        if child_old is None:
            # Object exists in new but not in old
            diff_info = {
                "category": CATEGORY_EXTRA, 
                "path": subpath, 
                "new": format_element(child_new)
            }
            append_diff(diffs, TYPE_EXTRA, diff_info)
        elif child_new is None:
            # Object exists in old but not in new
            diff_info = {
                "category": CATEGORY_MISSING, 
                "path": subpath, 
                "old": format_element(child_old)
            }
            append_diff(diffs, TYPE_MISSING, diff_info)
        else:
            # Object exists in both, compare them recursively
            diffs.extend(diff_elements(child_old, child_new, subpath))
    
    return diffs


def handle_default_children(old_list, new_list, path, tag):
    """Default comparison of children (by order)."""
    diffs = []
    max_len = max(len(old_list), len(new_list))
    
    for i in range(max_len):
        # Use a simpler path if there's only one child
        subpath = f"{path}.{tag}" if max_len == 1 else f"{path}.{tag}[{i}]"
        child_old = old_list[i] if i < len(old_list) else None
        child_new = new_list[i] if i < len(new_list) else None
        
        diffs.extend(diff_elements(child_old, child_new, subpath))
    
    return diffs


def filter_children(children):
    """Filter out attribute nodes that should be ignored."""
    ignored_names = {"sourcemodeldata", "destinationmodeldata", "mappingnumber"}
    return [
        child for child in children
        if not (child.tag == "attribute" and child.get("name") in ignored_names)
    ]


def diff_children(old_children, new_children, path):
    """Compare lists of child elements by grouping them by tag."""
    diffs = []
    
    # Filter out children that should be ignored
    old_children = filter_children(old_children)
    new_children = filter_children(new_children)

    # Group children by tag
    groups_old = group_by_tag(old_children)
    groups_new = group_by_tag(new_children)

    # Compare each group of tags
    for tag in set(groups_old.keys()).union(groups_new.keys()):
        old_list = groups_old.get(tag, [])
        new_list = groups_new.get(tag, [])
        
        # Use special handling for certain cases
        if tag == "key" and ".plist.dict" in path:
            diffs.extend(handle_plist_keys(old_list, new_list, path, tag))
        elif tag == "object":
            diffs.extend(handle_object_nodes(old_list, new_list, path))
        else:
            diffs.extend(handle_default_children(old_list, new_list, path, tag))
    
    return diffs


def group_by_tag(elements):
    """Group a list of elements by their tag."""
    groups = {}
    for element in elements:
        groups.setdefault(element.tag, []).append(element)
    return groups


def diff_elements(old_elem, new_elem, path):
    """Recursively compare two elements and return a list of differences."""
    diffs = []

    # Check for missing or extra nodes
    missing_diffs, both_present = check_missing_nodes(old_elem, new_elem, path)
    diffs.extend(missing_diffs)
    if not both_present:
        return diffs

    # Compare tag names
    tag_diffs = compare_tags(old_elem, new_elem, path)
    if tag_diffs:
        diffs.extend(tag_diffs)
        return diffs  # If tags differ, no need to go further

    # Compare text content and attributes
    diffs.extend(compare_text(old_elem, new_elem, path))
    diffs.extend(compare_attributes(old_elem, new_elem, path))

    # Compare child elements
    diffs.extend(diff_children(list(old_elem), list(new_elem), path))
    
    return diffs


def normalize_path(path):
    """Make paths more readable by using curly braces for object keys."""
    if "object[" in path:
        path = path.replace("object[", "object.{")
        if path.endswith("]"):
            path = path[:-1] + "}"
    return path


def print_differences(diffs):
    """Print all found differences in a readable format."""
    if not diffs:
        print("No differences found.")
        return

    # Group differences by error type
    error_dict = defaultdict(list)
    for err_type, msg in diffs:
        error_dict[err_type].append(msg)

    print("\nDifferences found (grouped by error type):")
    
    # Print each type of difference
    for err_type in sorted(error_dict.keys()):
        messages = error_dict[err_type]
        
        if err_type == TYPE_MISMATCH:
            print_mismatches(messages)
        elif err_type == TYPE_MISSING:
            print_missing_nodes(messages)
        elif err_type == TYPE_EXTRA:
            print_extra_nodes(messages)
        else:
            print_other_diffs(err_type, messages)


def print_mismatches(messages):
    """Print all mismatched elements."""
    print(f"\n=== MISMATCH ({len(messages)} occurrence{'s' if len(messages) != 1 else ''}) ===")
    print("Category: mismatching in old.xml and new.xml\n")
    
    for msg in messages:
        print(f"Path: {msg['path']}")
        print(f"  old = {msg['old']}")
        print(f"  new = {msg['new']}\n")


def print_missing_nodes(messages):
    """Print all nodes missing in the new XML."""
    print(f"\n=== MISSING NODE ({len(messages)} occurrence{'s' if len(messages) != 1 else ''}) ===")
    print(f"Category: {messages[0]['category']}\n")
    
    sorted_msgs = sorted(messages, key=lambda m: normalize_path(m["path"]))
    for msg in sorted_msgs:
        print(f"Path: {normalize_path(msg['path'])}")
        if "value" in msg and msg["value"]:
            print(f"  old = {msg['value']}")
        print("")


def print_extra_nodes(messages):
    """Print all extra nodes in the new XML."""
    print(f"\n=== EXTRA NODE ({len(messages)} occurrence{'s' if len(messages) != 1 else ''}) ===")
    print(f"Category: {messages[0]['category']}\n")
    
    sorted_msgs = sorted(messages, key=lambda m: normalize_path(m["path"]))
    for msg in sorted_msgs:
        print(f"Path: {normalize_path(msg['path'])}")
        if "value" in msg and msg["value"]:
            print(f"  new = {msg['value']}")
        print("")


def print_other_diffs(err_type, messages):
    """Print any other types of differences."""
    print(f"\n=== {err_type.upper()} ({len(messages)} occurrence{'s' if len(messages) != 1 else ''}) ===")
    for msg in messages:
        print(msg)
        print("")


def main():
    """Main function to compare two XML files."""
    try:
        tree_old = ET.parse("old.xml")
        tree_new = ET.parse("new.xml")
    except Exception as e:
        sys.exit(f"Error parsing XML files: {e}")

    root_old = tree_old.getroot()
    root_new = tree_new.getroot()
    
    # Find all differences between the two XML files
    diffs = diff_elements(root_old, root_new, root_old.tag)
    
    # Print the differences in a readable format
    print_differences(diffs)


if __name__ == "__main__":
    main()



### what is this for:
'''
1. when a model version is updated without regenerating the xcmappingmodel, the associated xcmappingmodel becomes out-of-date and coredata will ignore it even if it is present in the app bundle
2. to prevent this from happenning, one needs to regenerated the xcmappingmodel via xcode editor (File -> New -> New from template -> Mapping Model)
3. after regenerating the mappingmodel, one can use this utility to report the diff between old and new xcmappingmodel files so that one can be assured that regeneration of the xcmappingmodel 
   doesn't leave out any customizations that were present in the old xcmappingmodel ex: custom migration classes for entities etc.
'''

### How to invoke or use:
'''
    python SideStore/Utils/misc/xcmapping-diff-reporter/xcmapping-diff.py old.xcmappingmodel new.xcmappingmodel


// sample output
SideStore (develop-alpha) ✗ python SideStore/Utils/misc/xcmapping-diff-reporter/xcmapping-diff.py old.xcmappingmodel new.xcmappingmodel

Differences found (grouped by error type):

=== EXTRA NODE (16 occurrences) ===
Category: extra in new.xml

new = database.databaseInfo.metadata.plist.dict.key[1] text
new = database.databaseInfo.metadata.plist.dict.string[1]
new = database.object.{destination name: Account, mappingTypename: Undefined, mappingnumber: 2}
new = database.object.{destination name: AppID, mappingTypename: Undefined, mappingnumber: 1}
new = database.object.{destination name: AppPermission, mappingTypename: Undefined, mappingnumber: 12}
new = database.object.{destination name: AppVersion, mappingTypename: Undefined, mappingnumber: 5}
new = database.object.{destination name: InstalledApp, mappingTypename: Undefined, mappingnumber: 8}
new = database.object.{destination name: InstalledExtension, mappingTypename: Undefined, mappingnumber: 11}
new = database.object.{destination name: LoggedError, mappingTypename: Undefined, mappingnumber: 14}
new = database.object.{destination name: PatreonAccount, mappingTypename: Undefined, mappingnumber: 10}
new = database.object.{destination name: Patron, mappingTypename: Undefined, mappingnumber: 3}
new = database.object.{destination name: RefreshAttempt, mappingTypename: Undefined, mappingnumber: 13}
new = database.object.{destination name: Source, mappingTypename: Undefined, mappingnumber: 9}
new = database.object.{destination name: StoreApp, mappingTypename: Undefined, mappingnumber: 6}
new = database.object.{destination name: Team, mappingTypename: Undefined, mappingnumber: 4}
new = database.object.{name: hasUpdate}

=== MISMATCH (4 occurrences) ===
Category: mismatching in old.xml and new.xml

Path: database.databaseInfo.nextObjectID text
  old = 242
  new = 243

Path: database.databaseInfo.UUID text
  old = 53991141-FED9-4F4C-8444-9076589DBD8B
  new = E471EA1B-4480-40F0-BA79-DA9311928124

Path: database.databaseInfo.metadata.plist.dict.integer[0] text
  old = 1244
  new = 1419

Path: database.databaseInfo.metadata.plist.dict.string[0] text
  old = +Hmc2uYZK6og+Pvx5GUJ7oW75UG4V/ksQanTjfTKUnxyGWJRMtB5tIRgVwGsrd7lz/QR57++wbvWsr6nxwyS0A==
  new = bMpud663vz0bXQE24C6Rh4MvJ5jVnzsD2sI3njZkKbc=


=== MISSING NODE (13 occurrences) ===
Category: missing in new.xml while present in old.xml

old = database.object.{destination name: Account, mappingTypename: Undefined, mappingnumber: 4}
old = database.object.{destination name: AppID, mappingTypename: Undefined, mappingnumber: 11}
old = database.object.{destination name: AppPermission, mappingTypename: Undefined, mappingnumber: 3}
old = database.object.{destination name: AppVersion, mappingTypename: Undefined, mappingnumber: 10}
old = database.object.{destination name: InstalledApp, mappingTypename: Undefined, mappingnumber: 2}
old = database.object.{destination name: InstalledExtension, mappingTypename: Undefined, mappingnumber: 1}
old = database.object.{destination name: LoggedError, mappingTypename: Undefined, mappingnumber: 8}
old = database.object.{destination name: PatreonAccount, mappingTypename: Undefined, mappingnumber: 6}
old = database.object.{destination name: Patron, mappingTypename: Undefined, mappingnumber: 9}
old = database.object.{destination name: RefreshAttempt, mappingTypename: Undefined, mappingnumber: 5}
old = database.object.{destination name: Source, mappingTypename: Undefined, mappingnumber: 12}
old = database.object.{destination name: StoreApp, mappingTypename: Undefined, mappingnumber: 14}
old = database.object.{destination name: Team, mappingTypename: Undefined, mappingnumber: 13}

'''