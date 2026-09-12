#!/bin/bash
# ============================================================================
# XP-EHH Workflow Generator
# XP-EHH 工作流生成器
# ----------------------------------------------------------------------------
# Pipeline / 流程:
#   Split -> Impute/Phase -> Re-encode BGZF -> Extract populations
#   -> XP-EHH -> Merge
#   拆分 -> 填充定相 -> 重编码标准BGZF -> 提取群体 -> XP-EHH -> 合并
#
# Usage / 用法:
#   bash xp_ehh_pipeline.sh
#   bash xp_ehh_pipeline.sh --step 3
#   bash xp_ehh_pipeline.sh --chroms mylist.txt
#
# Notes / 说明:
#   - Standardization and its parameters are NOT included in this pipeline.
#     标准化步骤及其所需参数未包含在本流程内。
#   - Sub-scripts are generated per chromosome and can be submitted in parallel.
#     子脚本按染色体生成，可并行投递。
# ============================================================================
set -euo pipefail

# ============================================================================
# ===== Configuration / 配置区 =====
# ============================================================================
# Edit this section before running. Empty required fields will cause an early
# exit. Tools already in PATH can keep their default command names.
# 运行前请先编辑本区。必填项为空时脚本会提前退出；已在 PATH 中的工具
# 保持默认命令名即可。

# ----- Population definition / 群体定义 -----
REF_PREFIX=""              # Reference population prefix / 参考群体前缀
REF_GROUP=""               # Reference sample list file / 参考群体样本列表文件
COMP_PREFIX=""             # Comparison population prefix / 比对群体前缀
COMP_GROUP=""              # Comparison sample list file / 比对群体样本列表文件

# ----- Input VCF (all samples, indexed) / 输入 VCF（全部样本，需建索引）-----
INPUT_VCF=""

# ----- Tools / 工具 -----
# Prefer env override:  BCFTOOLS=/opt/bcftools BCFTOOLS=... bash xp_ehh_pipeline.sh
# 优先使用环境变量覆盖：BCFTOOLS=/opt/bcftools bash xp_ehh_pipeline.sh
BCFTOOLS="${BCFTOOLS:-bcftools}"
TABIX="${TABIX:-tabix}"
BGZIP="${BGZIP:-bgzip}"        # Used to re-encode Beagle output as BGZF / 用于重编码 Beagle 输出
SELSCAN="${SELSCAN:-selscan}"
JAVA="${JAVA:-java}"

# Absolute path to the Beagle jar (REQUIRED) / Beagle jar 绝对路径（必填）
BEAGLE_JAR="${BEAGLE_JAR:-}"

# Optional PATH prefix injected into generated sub-scripts.
# Leave empty to skip. Use ':' to separate multiple directories.
# 可选：注入到子脚本中的 PATH 前缀，留空则跳过；多个目录用 ':' 分隔。
EXTRA_PATH="${EXTRA_PATH:-}"

# ----- Parameters / 参数 -----
BEAGLE_MEM="40g"           # JVM heap for Beagle / Beagle JVM 内存
BEAGLE_THREADS=8           # Beagle threads / Beagle 线程数
SELSCAN_THREADS=4          # selscan threads / selscan 线程数

# ----- Chromosome list / 染色体列表 -----
CHROM_FILE="chromosomes.txt"

# ============================================================================
# ===== Argument parsing / 参数解析 =====
# ============================================================================
STEP="all"
while [[ $# -gt 0 ]]; do
    case $1 in
        --chroms) CHROM_FILE="$2"; shift 2 ;;
        --step)   STEP="$2"; shift 2 ;;
        *) echo "Unknown argument / 未知参数: $1"; exit 1 ;;
    esac
done

if [ ! -f "${CHROM_FILE}" ]; then
    echo "Error: chromosome list not found / 错误：染色体列表文件不存在: ${CHROM_FILE}"
    exit 1
fi

CHROM_LIST=()
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    if [[ "$line" =~ ^[0-9]+$ ]]; then
        CHROM_LIST+=("Chr${line}")
    else
        CHROM_LIST+=("$line")
    fi
done < "${CHROM_FILE}"

WORKDIR="$(pwd)"

# ----- Required config check / 必填配置校验 -----
# Fail early so we do not generate broken sub-scripts.
# 提前失败，避免生成缺变量/缺命令名的子脚本。
MISSING_CONF=()
require_conf() { [ -n "$2" ] || MISSING_CONF+=("$1"); }
require_conf INPUT_VCF   "${INPUT_VCF}"
require_conf REF_PREFIX  "${REF_PREFIX}"
require_conf REF_GROUP   "${REF_GROUP}"
require_conf COMP_PREFIX "${COMP_PREFIX}"
require_conf COMP_GROUP  "${COMP_GROUP}"
require_conf BEAGLE_JAR  "${BEAGLE_JAR}"

if [ ${#MISSING_CONF[@]} -gt 0 ]; then
    echo "Error: required config fields are empty / 错误：以下配置项为空，请填写后重跑："
    printf '  - %s\n' "${MISSING_CONF[@]}"
    echo "Hint: tools already in PATH can keep their default values."
    echo "提示：已在 PATH 中的工具可保持默认值。"
    exit 1
fi

if [ ${#CHROM_LIST[@]} -eq 0 ]; then
    echo "Error: no chromosome parsed from ${CHROM_FILE} / 错误：未从 ${CHROM_FILE} 解析到染色体"
    exit 1
fi

# Build the optional PATH export line for sub-scripts.
# 为子脚本构建可选的 PATH 导出语句。
PATH_EXPORT_LINE=""
[ -n "${EXTRA_PATH}" ] && PATH_EXPORT_LINE="export PATH=${EXTRA_PATH}:\$PATH"

echo "============================================"
echo "Chromosomes / 染色体数量 : ${#CHROM_LIST[@]}"
echo "Reference prefix / 参考群体前缀: ${REF_PREFIX}"
echo "Comparison prefix / 比对群体前缀: ${COMP_PREFIX}"
echo "Working dir / 工作目录: ${WORKDIR}"
echo "============================================"

# ============================================================================
# Step 1: Split chromosomes / 步骤1：拆分染色体
# ============================================================================
generate_step1() {
    echo ""
    echo ">>> Generating step 1: split chromosomes / 生成步骤1：拆分染色体..."
    mkdir -p 01_split_chr
    cd 01_split_chr

    for chr in "${CHROM_LIST[@]}"; do
        cat > run_split_${chr}.sh <<EOF
#!/bin/bash
set -e
${PATH_EXPORT_LINE}
# Note: input VCF must be indexed (.csi/.tbi).
# 注意：输入 VCF 需已建索引（.csi/.tbi）。
${BCFTOOLS} view -r ${chr} ${INPUT_VCF} -Oz -o ${WORKDIR}/01_split_chr/${chr}.vcf.gz
${TABIX} -p vcf ${WORKDIR}/01_split_chr/${chr}.vcf.gz
EOF
        chmod +x run_split_${chr}.sh
    done

    echo "  Generated ${#CHROM_LIST[@]} split scripts / 已生成 ${#CHROM_LIST[@]} 个拆分脚本"
    cd ..
}

# ============================================================================
# Step 2: Beagle imputation & phasing / 步骤2：Beagle 填充定相
# ============================================================================
generate_step2() {
    echo ""
    echo ">>> Generating step 2: Beagle imputation & phasing / 生成步骤2：Beagle 填充定相..."
    mkdir -p 02_beagle
    cd 02_beagle

    for chr in "${CHROM_LIST[@]}"; do
        cat > run_beagle_${chr}.sh <<EOF
#!/bin/bash
set -e
${PATH_EXPORT_LINE}
${JAVA} -Xmx${BEAGLE_MEM} -jar ${BEAGLE_JAR} \\
    gt=${WORKDIR}/01_split_chr/${chr}.vcf.gz \\
    out=${WORKDIR}/02_beagle/${chr}_phased \\
    nthreads=${BEAGLE_THREADS}

# ---- Re-encode to standard BGZF / 重编码为标准 BGZF ----
# Beagle writes a .vcf.gz that is NOT fully BGZF-compliant (missing EOF marker);
# htslib tools (bcftools / tabix / selscan) may fail or read nothing.
# Beagle 写出的 .vcf.gz 不符合规范 BGZF（块结尾缺 EOF 标记），htslib 工具
# （bcftools / tabix / selscan）读取时可能报错或读不到内容，需重新压缩。
# Do not enable pipefail here: zcat may return non-zero on a truncated file
# even when the decompressed payload is complete; validate the new file instead.
# 此处不要开启 pipefail：原文件缺 EOF 时 zcat 会返回非 0（但数据是完整的），
# 改为事后校验新文件。
phased=${WORKDIR}/02_beagle/${chr}_phased.vcf.gz
zcat "\${phased}" | ${BGZIP} -c > "\${phased}.recode.vcf.gz"
[ -s "\${phased}.recode.vcf.gz" ] || { echo "Error: empty recoded file / 重编码输出为空: \${phased}.recode.vcf.gz"; exit 1; }
${TABIX} -p vcf "\${phased}.recode.vcf.gz"
mv -f "\${phased}.recode.vcf.gz"     "\$phased"
mv -f "\${phased}.recode.vcf.gz.tbi" "\${phased}.tbi"
EOF
        chmod +x run_beagle_${chr}.sh
    done

    echo "  Generated ${#CHROM_LIST[@]} Beagle scripts / 已生成 ${#CHROM_LIST[@]} 个 Beagle 脚本"
    cd ..
}

# ============================================================================
# Step 3: Extract two populations / 步骤3：提取两个群体
# ============================================================================
generate_step3() {
    echo ""
    echo ">>> Generating step 3: extract populations / 生成步骤3：提取两个群体..."
    mkdir -p 03_extract
    cd 03_extract

    for chr in "${CHROM_LIST[@]}"; do
        cat > run_extract_${chr}.sh <<EOF
#!/bin/bash
set -e
${PATH_EXPORT_LINE}
# Input = re-encoded BGZF from step 2 / 输入 = 步骤2 重编码后的规范 BGZF

# Reference population / 参考群体
${BCFTOOLS} view -S ${WORKDIR}/${REF_GROUP} ${WORKDIR}/02_beagle/${chr}_phased.vcf.gz -Oz -o ${WORKDIR}/03_extract/${REF_PREFIX}_${chr}.vcf.gz
${TABIX} -p vcf ${WORKDIR}/03_extract/${REF_PREFIX}_${chr}.vcf.gz

# Comparison population / 比对群体
${BCFTOOLS} view -S ${WORKDIR}/${COMP_GROUP} ${WORKDIR}/02_beagle/${chr}_phased.vcf.gz -Oz -o ${WORKDIR}/03_extract/${COMP_PREFIX}_${chr}.vcf.gz
${TABIX} -p vcf ${WORKDIR}/03_extract/${COMP_PREFIX}_${chr}.vcf.gz
EOF
        chmod +x run_extract_${chr}.sh
    done

    echo "  Generated ${#CHROM_LIST[@]} extraction scripts / 已生成 ${#CHROM_LIST[@]} 个提取脚本"
    cd ..
}

# ============================================================================
# Step 4: XP-EHH with selscan / 步骤4：XP-EHH（selscan）
# ============================================================================
generate_step4() {
    echo ""
    echo ">>> Generating step 4: XP-EHH (selscan) / 生成步骤4：XP-EHH..."
    mkdir -p 04_xpehh
    cd 04_xpehh

    for chr in "${CHROM_LIST[@]}"; do
        cat > run_xpehh_${chr}.sh <<EOF
#!/bin/bash
set -e
${PATH_EXPORT_LINE}
# Inputs are phased, so --unphased is not needed.
# 输入已定相，因此不加 --unphased。
# Both VCFs must be tabix-indexed and sites must be aligned.
# 两个 VCF 均需已建 tabix 索引，且位点一一对应。
${SELSCAN} --xpehh \\
    --vcf-ref ${WORKDIR}/03_extract/${REF_PREFIX}_${chr}.vcf.gz \\
    --vcf     ${WORKDIR}/03_extract/${COMP_PREFIX}_${chr}.vcf.gz \\
    --pmap --threads ${SELSCAN_THREADS} \\
    --out ${WORKDIR}/04_xpehh/xpehh_phased_${chr}
EOF
        chmod +x run_xpehh_${chr}.sh
    done

    echo "  Generated ${#CHROM_LIST[@]} XP-EHH scripts / 已生成 ${#CHROM_LIST[@]} 个 XP-EHH 脚本"
    cd ..
}

# ============================================================================
# Step 5: Merge results / 步骤5：合并结果
# ============================================================================
generate_step5() {
    echo ""
    echo ">>> Generating step 5: merge results / 生成步骤5：合并结果..."
    mkdir -p 05_merge
    cd 05_merge

    CHR_LIST_STR="${CHROM_LIST[*]}"

    cat > merge_results.sh <<EOF
#!/bin/bash

CHR_LIST=(${CHR_LIST_STR})
WORKDIR=${WORKDIR}

# ----- Merge .out / 合并 .out -----
first_out=""
for chr in "\${CHR_LIST[@]}"; do
    f="\${WORKDIR}/04_xpehh/xpehh_phased_\${chr}.xpehh.out"
    if [ -f "\$f" ]; then
        first_out="\$f"
        break
    fi
done

if [ -z "\$first_out" ]; then
    echo "Error: no .xpehh.out found / 错误：未找到任何 .xpehh.out 文件"
    exit 1
fi

head -n 1 "\$first_out" > "\${WORKDIR}/05_merge/phased_all.xpehh.out"
for chr in "\${CHR_LIST[@]}"; do
    f="\${WORKDIR}/04_xpehh/xpehh_phased_\${chr}.xpehh.out"
    if [ -f "\$f" ]; then
        tail -n +2 "\$f" >> "\${WORKDIR}/05_merge/phased_all.xpehh.out"
    fi
done
echo "Merged: phased_all.xpehh.out / 合并完成"

# ----- Merge .norm / 合并 .norm -----
first_norm=""
for chr in "\${CHR_LIST[@]}"; do
    f="\${WORKDIR}/04_xpehh/xpehh_phased_\${chr}.xpehh.norm"
    if [ -f "\$f" ]; then
        first_norm="\$f"
        break
    fi
done

if [ -n "\$first_norm" ]; then
    head -n 1 "\$first_norm" > "\${WORKDIR}/05_merge/phased_all.xpehh.norm"
    for chr in "\${CHR_LIST[@]}"; do
        f="\${WORKDIR}/04_xpehh/xpehh_phased_\${chr}.xpehh.norm"
        if [ -f "\$f" ]; then
            tail -n +2 "\$f" >> "\${WORKDIR}/05_merge/phased_all.xpehh.norm"
        fi
    done
    echo "Merged: phased_all.xpehh.norm / 合并完成"
fi

# ----- Verify / 验证 -----
echo ""
echo "========== Merge verification / 合并结果验证 =========="
echo "phased_all.xpehh.out lines / 总行数: \$(wc -l < "\${WORKDIR}/05_merge/phased_all.xpehh.out")"
EOF
    chmod +x merge_results.sh

    echo "  Generated 05_merge/merge_results.sh / 已生成 05_merge/merge_results.sh"
    cd ..
}

# ============================================================================
# Main / 主逻辑
# ============================================================================
case "${STEP}" in
    all)
        generate_step1
        generate_step2
        generate_step3
        generate_step4
        generate_step5
        ;;
    1) generate_step1 ;;
    2) generate_step2 ;;
    3) generate_step3 ;;
    4) generate_step4 ;;
    5) generate_step5 ;;
    *)
        echo "Invalid step / 无效的步骤: ${STEP}. Valid: all, 1, 2, 3, 4, 5"
        exit 1
        ;;
esac

echo ""
echo "============================================"
echo "Done! Directory layout / 生成完成！目录结构："
echo "  01_split_chr/   - Split scripts / 拆分染色体脚本"
echo "  02_beagle/      - Beagle phasing scripts / Beagle 填充定相脚本"
echo "  03_extract/     - Population extraction scripts / 提取群体脚本"
echo "  04_xpehh/       - XP-EHH scripts / XP-EHH 脚本"
echo "  05_merge/       - Merge scripts / 合并结果脚本"
echo "============================================"