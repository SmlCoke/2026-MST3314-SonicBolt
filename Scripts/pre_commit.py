#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys
import os
import re
import subprocess
from datetime import date


def configure_stdio():
    """尽最大努力使用 UTF-8 输出，避免 Windows 控制台编码导致异常。"""
    try:
        if hasattr(sys.stdout, "reconfigure"):
            sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
        if hasattr(sys.stderr, "reconfigure"):
            sys.stderr.reconfigure(encoding="utf-8", errors="backslashreplace")
    except Exception:
        # 某些运行环境不支持 reconfigure，直接回退默认行为
        pass


def safe_print(*args, sep=" ", end="\n", file=None, flush=False):
    """兼容 GBK 等编码环境，避免打印 Unicode 字符导致 pre-commit 直接崩溃。"""
    if file is None:
        file = sys.stdout

    text = sep.join(str(arg) for arg in args) + end
    try:
        file.write(text)
    except UnicodeEncodeError:
        encoding = getattr(file, "encoding", None) or "utf-8"
        if hasattr(file, "buffer"):
            file.buffer.write(text.encode(encoding, errors="backslashreplace"))
        else:
            fallback = text.encode("ascii", errors="backslashreplace").decode("ascii")
            file.write(fallback)

    if flush:
        try:
            file.flush()
        except Exception:
            pass


print = safe_print

# ========== 版本号检查配置 ==========
CONV_README_PATH = "SonicBolt/src/conv/docs/README.md"
CONV_MAIN_V_PATH = "SonicBolt/src/conv/conv_subsystem.v"

DWCONV_README_PATH = "SonicBolt/src/dwconv/docs/README.md"
DWCONV_MAIN_V_PATH = "SonicBolt/src/dwconv/dwconv_subsystem.v"

PWCONV_README_PATH = "SonicBolt/src/pwconv/docs/README.md"
PWCONV_MAIN_V_PATH = "SonicBolt/src/pwconv/pwconv_subsystem.v"

POST_README_PATH = "SonicBolt/src/post_process/docs/README.md"
POST_MAIN_V_PATH = "SonicBolt/src/post_process/post_process_subsystem.v"

CNN_README_PATH = "SonicBolt/README.md"
PROJECT_README_PATH = "README.md"

def get_line(file_path, line_number):
    """获取指定文件的特定行（行号从1开始）"""
    if not os.path.exists(file_path):
        print(f"❌ 拦截: 找不到文件 {file_path}")
        sys.exit(1)

    with open(file_path, "r", encoding="utf-8") as f:
        lines = f.readlines()
        if len(lines) < line_number:
            print(f"❌ 拦截: {file_path} 行数不足 {line_number} 行")
            sys.exit(1)
        return lines[line_number - 1].strip()

def extract_version(text, file_path, line_number):
    """从文本中提取版本号，格式为 vx.y（例如 v2.2）"""
    match = re.search(r"v\d+\.\d+", text)
    if not match:
        print(f"❌ 拦截: 在 {file_path} 第 {line_number} 行未找到版本号(vx.y)")
        print(f"📄 行内容: '{text}'")
        sys.exit(1)
    return match.group(0)

def check_version_consistency():
    print("⏳ 正在执行 pre-commit 检查：验证版本号一致性...")

    # 获取 Conv 层顶层子系统的版本号行
    conv_readme_line = get_line(CONV_README_PATH, 3)
    conv_main_line = get_line(CONV_MAIN_V_PATH, 6)

    # 获取 DWConv 层顶层子系统的版本号行
    dwconv_readme_line = get_line(DWCONV_README_PATH, 3)
    dwconv_main_line = get_line(DWCONV_MAIN_V_PATH, 6)

    # 获取 PWConv 层顶层子系统的版本号行
    pwconv_readme_line = get_line(PWCONV_README_PATH, 3)
    pwconv_main_line = get_line(PWCONV_MAIN_V_PATH, 6)

    # 获取 Post-Process 层顶层子系统的版本号行
    post_readme_line = get_line(POST_README_PATH, 3)
    post_main_line = get_line(POST_MAIN_V_PATH, 6)

    # 获取 Conv 层子系统版本号
    conv_readme_version = extract_version(conv_readme_line, CONV_README_PATH, 3)
    conv_main_version = extract_version(conv_main_line, CONV_MAIN_V_PATH, 6)

    # 获取 DWConv 层子系统版本号
    dwconv_readme_version = extract_version(dwconv_readme_line, DWCONV_README_PATH, 3)
    dwconv_main_version = extract_version(dwconv_main_line, DWCONV_MAIN_V_PATH, 6)

    # 获取 PWConv 层子系统版本号
    pwconv_readme_version = extract_version(pwconv_readme_line, PWCONV_README_PATH, 3)
    pwconv_main_version = extract_version(pwconv_main_line, PWCONV_MAIN_V_PATH, 6)

    # 获取 Post-Process 层子系统版本号
    post_readme_version = extract_version(post_readme_line, POST_README_PATH, 3)
    post_main_version = extract_version(post_main_line, POST_MAIN_V_PATH, 6)

    # 检查项目 README 指定的 CNN 系统版本号与 CNN README.md 中的版本号是否一致
    cnn_readme_line = get_line(CNN_README_PATH, 3)
    project_readme_line = get_line(PROJECT_README_PATH, 6)
    cnn_readme_version = extract_version(cnn_readme_line, CNN_README_PATH, 3)
    project_readme_version = extract_version(project_readme_line, PROJECT_README_PATH, 6)


    # ---------- 检查各组版本号是否一致 ----------
    if conv_readme_version != conv_main_version:
        print("\n🚫 Commit 被拒绝！版本号不匹配！")
        print(f"📄 {CONV_README_PATH} 第 3 行版本: '{conv_readme_version}'")
        print(f"📄 {CONV_MAIN_V_PATH} 第 6 行版本: '{conv_main_version}'")
        print("💡 请修改对齐后再重新执行 git commit。")
        sys.exit(1)

    if dwconv_readme_version != dwconv_main_version:
        print("\n🚫 Commit 被拒绝！版本号不匹配！")
        print(f"📄 {DWCONV_README_PATH} 第 3 行版本: '{dwconv_readme_version}'")
        print(f"📄 {DWCONV_MAIN_V_PATH} 第 6 行版本: '{dwconv_main_version}'")
        print("💡 请修改对齐后再重新执行 git commit。")
        sys.exit(1)

    if pwconv_readme_version != pwconv_main_version:
        print("\n🚫 Commit 被拒绝！版本号不匹配！")
        print(f"📄 {PWCONV_README_PATH} 第 3 行版本: '{pwconv_readme_version}'")
        print(f"📄 {PWCONV_MAIN_V_PATH} 第 6 行版本: '{pwconv_main_version}'")
        print("💡 请修改对齐后再重新执行 git commit。")
        sys.exit(1)

    if post_readme_version != post_main_version:
        print("\n🚫 Commit 被拒绝！版本号不匹配！")
        print(f"📄 {POST_README_PATH} 第 3 行版本: '{post_readme_version}'")
        print(f"📄 {POST_MAIN_V_PATH} 第 6 行版本: '{post_main_version}'")
        print("💡 请修改对齐后再重新执行 git commit。")
        sys.exit(1)

    if cnn_readme_version != project_readme_version:
        print("\n🚫 Commit 被拒绝！版本号不匹配！")
        print(f"📄 {CNN_README_PATH} 第 3 行版本: '{cnn_readme_version}'")
        print(f"📄 {PROJECT_README_PATH} 第 6 行版本: '{project_readme_version}'")
        print("💡 请修改对齐后再重新执行 git commit。")
        sys.exit(1)
        
    print("✅ 版本号校验通过。")

# ========== 新增：检查 staged 的 .v 文件日期 ==========
def get_staged_v_files():
    """
    获取本次提交暂存区中的 .v 文件（新增/修改/复制/重命名）
    """
    cmd = [
        "git", "diff", "--cached", "--name-only",
        "--diff-filter=ACMR"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True, encoding="utf-8")
    files = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    return [f for f in files if f.endswith(".v")]

def read_staged_file_content(path):
    """
    读取暂存区版本的文件内容（不是工作区）
    """
    # 用 "git show :path" 读取 index 中该文件
    result = subprocess.run(
        ["git", "show", f":{path}"],
        capture_output=True,
        text=True,
        encoding="utf-8"
    )
    if result.returncode != 0:
        # 某些极端情况（如子模块、路径异常）做兜底
        print(f"❌ 拦截: 无法读取暂存区文件内容: {path}")
        print(result.stderr.strip())
        sys.exit(1)
    return result.stdout

def check_v_file_dates():
    print("⏳ 正在执行 pre-commit 检查：验证 staged .v 文件中的日期...")

    staged_v_files = get_staged_v_files()
    if not staged_v_files:
        print("ℹ️ 本次提交未包含 .v 文件，跳过日期检查。")
        return

    today = date.today().isoformat()  # YYYY-MM-DD
    expected_line = f"* 日期: {today}"

    missing_or_wrong = []

    # 匹配 "* 日期: 2026-03-28"（允许前后空格）
    date_line_pattern = re.compile(r"^\s*\*\s*日期:\s*(\d{4}-\d{2}-\d{2})\s*$", re.MULTILINE)

    for file_path in staged_v_files:
        content = read_staged_file_content(file_path)
        if not content:
            raise ValueError(f"无法读取文件内容: {file_path}")
        matches = date_line_pattern.findall(content)

        if not matches:
            missing_or_wrong.append((file_path, "缺少日期行", None))
            continue

        # 只要存在任意一行日期=今天，就通过
        if today not in matches:
            missing_or_wrong.append((file_path, "日期不是当天", matches))

    if missing_or_wrong:
        print("\n🚫 Commit 被拒绝！以下 .v 文件日期不合规：")
        for fp, reason, found in missing_or_wrong:
            if reason == "缺少日期行":
                print(f" - {fp}: 未找到形如 '* 日期: YYYY-MM-DD' 的行")
            else:
                print(f" - {fp}: 找到日期 {found}，但今天应为 {today}")
        print(f"\n💡 请确保每个 staged 的 .v 文件包含：'{expected_line}'")
        sys.exit(1)

    print("✅ .v 文件日期校验通过。")

def main():
    configure_stdio()
    try:
        check_version_consistency()
        check_v_file_dates()
    except subprocess.CalledProcessError as e:
        print("❌ 拦截: 执行 git 命令失败")
        print(e)
        sys.exit(1)

    print("\n🎉 所有 pre-commit 检查通过，允许 Commit！")
    sys.exit(0)

if __name__ == "__main__":
    main()