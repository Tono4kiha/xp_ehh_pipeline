# XP-EHH Pipeline

A Bash-based workflow generator for genome-wide XP-EHH scans.

一个用于全基因组 XP-EHH 扫描的工作流生成脚本。

---

## Overview / 概述

This pipeline generates per-chromosome sub-scripts and runs them in parallel:

本流程按染色体生成子脚本并支持并行投递，主要步骤为：

```text
Split -> Impute/Phase -> Re-encode BGZF -> Extract populations -> XP-EHH -> Merge
拆分  -> 填充定相     -> 重编码标准BGZF -> 提取群体          -> XP-EHH -> 合并
```

Each step writes its scripts into a dedicated directory so that the workflow
can be re-run or resumed from any intermediate stage.

每一步都会在对应目录下生成独立脚本，便于重跑或从中间步骤继续。

---

## Requirements / 依赖

- `bcftools`
- `tabix`
- `bgzip`
- `selscan`
- Java 8+ and a Beagle jar file

The tools above should be available in `PATH`, or their absolute paths should
be provided through environment variables (see Configuration).

以上工具应位于 `PATH` 中，或通过环境变量提供其绝对路径（见配置说明）。

---

## Repository Layout / 目录结构

```text
.
├── xp_ehh_pipeline.sh   # Main workflow generator / 主工作流生成脚本
├── chromosomes.txt      # Example chromosome list / 示例染色体列表
└── README.md
```

---

## Configuration / 配置

All settings are located in the **Configuration** section at the top of
`xp_ehh_pipeline.sh`. Required fields must be filled in before running.

所有配置位于 `xp_ehh_pipeline.sh` 顶部的 **Configuration** 区。必填项在运行前
必须填写，否则脚本会提前退出。

### Required fields / 必填项

| Variable      | Description                              |
| ------------- | ---------------------------------------- |
| `REF_PREFIX`  | Reference population prefix              |
| `REF_GROUP`   | Reference sample list file               |
| `COMP_PREFIX` | Comparison population prefix             |
| `COMP_GROUP`  | Comparison sample list file              |
| `INPUT_VCF`   | Indexed VCF containing all samples       |
| `BEAGLE_JAR`  | Absolute path to the Beagle jar          |

### Tools / 工具

Tool variables default to their command names and can be overridden via
environment variables:

工具变量默认使用命令名，可通过环境变量覆盖：

```text
BCFTOOLS=bcftools
TABIX=tabix
BGZIP=bgzip
SELSCAN=selscan
JAVA=java
```

Example / 示例：

```text
BCFTOOLS=/opt/bcftools/bin/bcftools \
SELSCAN=/opt/selscan/bin/selscan \
xp_ehh_pipeline.sh
```

### Optional / 可选

| Variable         | Description                                         |
| ---------------- | --------------------------------------------------- |
| `EXTRA_PATH`     | PATH prefix injected into sub-scripts; empty = skip |
| `BEAGLE_MEM`     | JVM heap for Beagle (e.g. `40g`)                    |
| `BEAGLE_THREADS` | Beagle threads                                      |
| `SELSCAN_THREADS`| selscan threads                                     |

---

## Usage / 用法

```text
# Generate all step scripts
# 生成全部步骤脚本
xp_ehh_pipeline.sh

# Generate only step 3
# 只生成步骤 3
xp_ehh_pipeline.sh --step 3

# Use a custom chromosome list
# 使用自定义染色体列表
xp_ehh_pipeline.sh --chroms mylist.txt
```

Note: `--step` accepts `all`, `1`, `2`, `3`, `4`, or `5`.

说明：`--step` 可选值为 `all`、`1`、`2`、`3`、`4`、`5`。

---

## Chromosome List Format / 染色体列表格式

One chromosome per line. Lines starting with `#` and empty lines are ignored.
Pure numeric entries are automatically prefixed with `Chr`.

每行一个染色体，`#` 开头的行和空行会被忽略。纯数字会自动加 `Chr` 前缀。

```text
# Example / 示例
1
2
ChrX
```

---

## Input Files / 输入文件

- An indexed VCF (`INPUT_VCF`) containing all samples.
  包含全部样本、已建索引的 VCF。
- Two sample list files (`REF_GROUP`, `COMP_GROUP`), one sample per line.
  两个样本列表文件（`REF_GROUP`、`COMP_GROUP`），每行一个样本。

---

## Output Layout / 输出目录

```text
01_split_chr/   Split scripts / 拆分染色体脚本
02_beagle/      Beagle phasing scripts / Beagle 填充定相脚本
03_extract/     Population extraction scripts / 提取群体脚本
04_xpehh/       XP-EHH scripts / XP-EHH 脚本
05_merge/       Merge scripts / 合并结果脚本
```

Final merged results / 最终合并结果：

```text
05_merge/phased_all.xpehh.out
05_merge/phased_all.xpehh.norm
```

---

## Notes / 注意事项

- Beagle writes `.vcf.gz` files that are not fully BGZF-compliant; the
  pipeline re-encodes them with `bgzip` before downstream steps.
  Beagle 写出的 `.vcf.gz` 不符合规范 BGZF，流程会先用 `bgzip` 重编码后再进入
  后续步骤。
- `selscan` is called with `--vcf-ref` for the reference population and `--vcf`
  for the comparison population. Both VCFs must be tabix-indexed and share
  aligned sites.
  `selscan` 参考群体使用 `--vcf-ref`，比对群体使用 `--vcf`；两个 VCF 均需建
  tabix 索引，且位点一一对应。
- Inputs are phased, so `--unphased` is not used.
  输入已定相，因此不使用 `--unphased`。
- **Standardization and its parameters are NOT included in this pipeline.**
  **标准化步骤及其所需参数未包含在本流程内。**
- Sub-scripts are generated per chromosome; parallel submission (e.g. with a
  scheduler) is left to the user.
  子脚本按染色体生成；是否并行投递（如提交到调度系统）由用户自行处理。
```
<table>
  <tr>
    <td>中文名</td>
    <td>Name</td>
    <td>E-mail</td>
    <td>Blog / Other</td>
  </tr>
  <tr>
    <td>李硕</td>
    <td>Biols0208</td>
    <td>lishuo6008@outlook.com</td>
    <td>https://bioinformls.com  https://www.researchgate.net/profile/Shuo_Li37</td>
  </tr>
  <tr>
    <td>靳展</td>
    <td>Tono4kiha</td>
    <td>1165777233@qq.com</td>
    <td>https://github.com/Tono4kiha</td>
  </tr>
</table>
