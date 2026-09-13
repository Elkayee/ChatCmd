# kiem_tra_skills_va_context.py
# Kich ban kiem tra toan dien co che Find Skills va nap Context (task.md, plan.md, AGENTS.md) cho ChatCMD

import os
import sys
import re
from pathlib import Path

# Dam bao terminal ho tro UTF-8
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


def ktra_block_scalar(gtri):
    """Kiem tra chuoi co phai chi thi YAML block scalar (>-, |-, >+, |+, >) khong."""
    s = gtri.strip()
    s = s.split("#")[0].strip()
    if s.startswith(">") or s.startswith("|"):
        phan_con = s[1:]
        return all(c.isdigit() or c in "-+" for c in phan_con)
    return False


def doc_frontmatter_skill(tep_skill):
    """Trich xuat frontmatter cua SKILL.md theo thuat toan Rust da duoc toi uu."""
    try:
        txt = Path(tep_skill).read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return {}

    lines = txt.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}

    kq = {}
    khoa_ml = None
    dem_dong = []

    for d in lines[1:]:
        if d.strip() == "---":
            if khoa_ml and dem_dong:
                kq[khoa_ml] = " ".join(dem_dong).strip()
            break

        if khoa_ml:
            if d.startswith(" ") or d.startswith("\t"):
                nd = d.strip()
                if nd:
                    dem_dong.append(nd)
                continue
            elif not d.strip():
                continue
            else:
                kq[khoa_ml] = " ".join(dem_dong).strip()
                khoa_ml = None
                dem_dong = []

        if ":" in d:
            k, v = d.split(":", 1)
            k = k.strip()
            v = v.strip()
            if ktra_block_scalar(v):
                khoa_ml = k
                dem_dong = []
            else:
                kq[k] = v.strip("\"'")

    return kq


def tim_kiem_skills(ds_sk, tu_khoa, gioi_han=5):
    """Xep hang tim kiem 4 cap do giong Rust search_for_workspace."""
    tk = tu_khoa.lower().strip()
    tokens = [t for t in re.split(r"[^a-zA-Z0-9]+", tk) if t]
    kq = []

    for s in ds_sk:
        ten = s.get("name", "").lower()
        mieu_ta = s.get("description", "").lower()
        score = 0

        if not tk:
            score = 1
        elif ten == tk:
            score = 4
        elif ten.startswith(tk):
            score = 3
        else:
            chuoi_tim = f"{ten} {mieu_ta}"
            khop = sum(1 for tok in tokens if re.search(r"\b" + re.escape(tok), chuoi_tim))
            if khop == len(tokens) and khop > 0:
                score = 2
            elif khop > 0:
                score = 1

        if score > 0:
            kq.append((score, s))

    # Sap xep diem cao len truoc, sau do theo ten
    kq.sort(key=lambda x: (-x[0], x[1].get("name", "")))
    return [item[1] for item in kq[:gioi_han]]


def kiem_tra_find_skills_thuc_te():
    """Quet toan bo skills trong he thong va do kich thuoc payload."""
    print("=== [PHAN 1: KIEM TRA TRIGGER VA FIND SKILLS CUA CHATCMD] ===")
    tm_goc = Path.home() / ".agents" / "skills"
    if not tm_goc.exists():
        tm_goc = Path.home() / ".codex" / "skills"

    ds_skills = []
    if tm_goc.exists():
        for d in tm_goc.iterdir():
            tep = d / "SKILL.md"
            if tep.is_file():
                fm = doc_frontmatter_skill(tep)
                if fm:
                    ds_skills.append(fm)

    print(f"-> Tong so skills phat hien: {len(ds_skills)}")

    # Kiem tra cac skill nhay cam de xac minh loi parse YAML da duoc fix
    cac_skill_test = ["orchestration", "ida-reverse", "browser-automation", "radare2"]
    print("\n-> Kiem tra do dai description cua cac skill thuong dung block chomping (>-, |-):")
    for ten in cac_skill_test:
        sk = next((s for s in ds_skills if s.get("name") == ten), None)
        if sk:
            desc = sk.get("description", "")
            hop_le = len(desc) > 10 and not desc.startswith(">-") and not desc.startswith("|-")
            trang_thai = "[OK - HOP LE]" if hop_le else "[FAIL - BI LOI]"
            print(f"   * {ten:<22}: {trang_thai} (Do dai: {len(desc)} ky tu)")
            print(f"     Trích đoạn: {desc[:90]}...")
        else:
            print(f"   * {ten:<22}: [Chua cai dat]")

    # Kiem tra do phinh to payload
    import json
    xau_toan_bo = json.dumps(ds_skills, ensure_ascii=False)
    kb_cu = len(xau_toan_bo.encode("utf-8")) / 1024

    top_find = tim_kiem_skills(ds_skills, "reverse engineering disassemble", gioi_han=5)
    xau_find = json.dumps(top_find, ensure_ascii=False)
    kb_moi = len(xau_find.encode("utf-8")) / 1024

    print(f"\n-> So sanh dung luong payload:")
    print(f"   * skills_list (149 skills)      : {kb_cu:.2f} KB (~{int(kb_cu*230)} tokens)")
    print(f"   * skills_search (Top 5 tim kiem): {kb_moi:.2f} KB (~{int(kb_moi*230)} tokens)")
    print(f"   * Ti le tiet kiem               : Giảm {((kb_cu - kb_moi)/kb_cu)*100:.1f}%!")
    print(f"   * Cac skill tim duoc theo 'reverse engineering disassemble':")
    for s in top_find:
        print(f"     + {s.get('name')}: {s.get('description')[:70]}...")


def kiem_tra_kich_hoat_context_chatcmd():
    """Kiem tra viec tu dong kich hoat task.md, plan.md, AGENTS.md khi workspace la ChatCmd."""
    print("\n=== [PHAN 2: KIEM TRA TU DONG KICH HOAT TASK.MD, PLAN.MD, AGENTS.MD CHO CHATCMD] ===")
    tm_chatcmd = Path(r"C:\Tools\ChatCmd")

    # 1. Kiem tra AGENTS.md
    tep_ag = tm_chatcmd / "AGENTS.md"
    print(f"-> 1. AGENTS.md tai ChatCMD:")
    if tep_ag.exists():
        txt_ag = tep_ag.read_text(encoding="utf-8", errors="ignore")
        print(f"   * Ton tai: Co ({len(txt_ag)} bytes)")
        print(f"   * Trich tieu de: {txt_ag.splitlines()[0]}")
    else:
        print("   * Khong ton tai")

    # 2. Kiem tra plan.md hoac plan/
    print(f"-> 2. Plan/Spec tai ChatCMD:")
    tm_plan = tm_chatcmd / "plan"
    tep_plan = tm_chatcmd / "plan.md"
    if tep_plan.exists():
        print(f"   * Tim thay plan.md o thu muc goc")
    elif tm_plan.exists():
        ds_plan = list(tm_plan.glob("*.md"))
        print(f"   * Tim thay thu muc plan/ voi {len(ds_plan)} files ke hoach:")
        for p in ds_plan[:3]:
            print(f"     + {p.name}")

    # 3. Kiem tra task.md
    tep_task = tm_chatcmd / "task.md"
    print(f"-> 3. Task checklist tai ChatCMD (task.md):")
    if tep_task.exists():
        txt_task = tep_task.read_text(encoding="utf-8", errors="ignore")
        dong_tasks = [d.strip() for d in txt_task.splitlines() if re.match(r"^\s*-\s*\[[ xX]\]", d)]
        dem_xong = sum(1 for d in dong_tasks if re.match(r"^\s*-\s*\[[xX]\]", d))
        dem_chua = len(dong_tasks) - dem_xong
        print(f"   * Tong so tasks phat hien: {len(dong_tasks)}")
        print(f"   * Da hoan thanh [x]      : {dem_xong}")
        print(f"   * Dang cho xu ly [ ]     : {dem_chua}")
        print("   * 3 Task gan nhat:")
        for t in dong_tasks[:3]:
            print(f"     {t}")
    else:
        print("   * Khong tim thay task.md")


if __name__ == "__main__":
    kiem_tra_find_skills_thuc_te()
    kiem_tra_kich_hoat_context_chatcmd()
