#################
#### Somatic ####
from umccrise import get_cancer_genes_ensg
from python_utils import hpc


localrules: small_variants


# Preparations: annotate TUMOR_X and NORMAL_X fields, remove non-standard chromosomes and mitochondria, remove non-PASSed calls.
# Suites for PCGR, but for all other processing steps too
rule somatic_vcf_prep:  # {batch}
    input:
        vcf = lambda wc: join(run.date_dir, f'{batch_by_name[wc.batch].name}-ensemble-annotated.vcf.gz')
    output:
        vcf = '{batch}/work/small_variants/somatic-ensemble-prep.vcf.gz',
        tbi = '{batch}/work/small_variants/somatic-ensemble-prep.vcf.gz.tbi'
    shell:
        'pcgr_prep {input.vcf} |'
        ' bcftools view -f.,PASS -Oz -o {output.vcf}'
        ' && tabix -p vcf {output.vcf}'

# Bcbio doesn't properly filter Strelka2 and MuTect2 calls, so need to post-filter
rule somatic_vcf_filter_af:  # {batch}
    input:
        vcf = rules.somatic_vcf_prep.output.vcf
    params:
        min_af = 0.1
    output:
        vcf = '{batch}/work/small_variants/somatic-ensemble-prep-min_af.vcf.gz',
        tbi = '{batch}/work/small_variants/somatic-ensemble-prep-min_af.vcf.gz.tbi'
    shell:
        'bcftools filter -e "TUMOR_AF<0.1" {input.vcf} -Oz -o {output.vcf} && tabix {output.vcf}'

rule somatic_vcf_pon:  # {batch}
    input:
        vcf = rules.somatic_vcf_filter_af.output.vcf,
        tbi = rules.somatic_vcf_filter_af.output.tbi
    params:
        genome_build = run.genome_build,
        pon_exists = hpc.ref_file_exists(run.genome_build, 'panel_of_normals_dir'),
        ht = 1
    output:
        vcf = '{batch}/small_variants/{batch}-somatic-ensemble-pon_softfiltered.vcf.gz',
        tbi = '{batch}/small_variants/{batch}-somatic-ensemble-pon_softfiltered.vcf.gz.tbi'
    run:
        if params.pon_exists:
            shell('pon_anno {input.vcf} -h {params.ht} -o {output.vcf} -g {params.genome_build} && tabix -p vcf {output.vcf}')
        else:
            shell('cp {input.vcf} {output.vcf} && cp {input.tbi} {output.tbi}')

rule somatic_vcf_pon_pass:  # {batch}
    input:
        rules.somatic_vcf_pon.output.vcf
    output:
        vcf = '{batch}/small_variants/{batch}-somatic-ensemble-pon_hardfiltered.vcf.gz',
        tbi = '{batch}/small_variants/{batch}-somatic-ensemble-pon_hardfiltered.vcf.gz.tbi'
    shell:
        'bcftools view -f.,PASS -Oz {input} -o {output.vcf}'
        ' && tabix -p vcf {output.vcf}'

##################
#### Germline ####
# Annotate any events found in Sean's 105/106 cancer predisposition gene set.
rule germline_vcf_subset:  # {batch}
    input:
        vcf = lambda wc: join(run.date_dir, f'{batch_by_name[wc.batch].normal.name}-ensemble-annotated.vcf.gz'),
        ensg = get_cancer_genes_ensg()
    output:
        vcf = '{batch}/work/small_variants/raw_normal-ensemble-cancer_genes.vcf.gz',
        tbi = '{batch}/work/small_variants/raw_normal-ensemble-cancer_genes.vcf.gz.tbi'
    params:
        ungz = lambda wc, output: get_ungz_gz(output[0])[0]
    shell:
        'zgrep ^# {input.vcf} > {params.ungz}'
        ' && zgrep -f {input.ensg} {input.vcf} >> {params.ungz}'
        ' && bgzip {params.ungz}'
        ' && tabix -p vcf {output.vcf}'

# Preparations: annotate TUMOR_X and NORMAL_X fields, remove non-standard chromosomes and mitochondria, remove non-PASSed calls.
# Suites for PCGR, but for all other processing steps too
rule germline_vcf_prep:
    input:
        vcf = rules.germline_vcf_subset.output.vcf
    output:
        vcf = '{batch}/small_variants/{batch}-normal-ensemble-cancer_genes.vcf.gz',
        tbi = '{batch}/small_variants/{batch}-normal-ensemble-cancer_genes.vcf.gz.tbi'
    shell:
        'pcgr_prep {input.vcf} |'
        ' bcftools view -f.,PASS -Oz -o {output.vcf}'
        ' && tabix -p vcf {output.vcf}'


#############

rule small_variants:
    input:
        expand(rules.somatic_vcf_pon_pass.output, batch=batch_by_name.keys()),
        expand(rules.germline_vcf_prep.output, batch=batch_by_name.keys())
    output:
        temp(touch('small_variants.done'))