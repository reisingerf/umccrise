from cyvcf2 import VCF

"""
Structural variants
------------------
Re-do the CNV plots. This will need lots of love (drop gene names, make the scatterplot viable again, etc.).
"""
vcftobedpe = 'vcfToBedpe'


localrules: structural


#######################
######### CNV #########

#### Drop gene labels
rule cnvkit_cleanup:
    input:
        lambda wc: join(batch_by_name[wc.batch].tumor.dirpath, f'{batch_by_name[wc.batch].name}-cnvkit-call.cns')
    output:
        'work/{batch}/structural/{batch}-cnvkit-nolabels.cns'
    group: "cnvkit_plot"
    shell:
        'cat {input}'
        ' | grep -v ^GL '
        ' | py -x "\'\\t\'.join((x.split()[:3] + [\'.\', x.split()[4]]) if not x.startswith(\'chromosome\') else x.split()[:5])"'
        ' > {output}'

#### Plot
rule cnvkit_plot:
    input:
        rules.cnvkit_cleanup.output[0]
    output:
        '{batch}/structural/{batch}-cnvkit-diagram.pdf'
    group: "cnvkit_plot"
    shell:
        'cnvkit.py diagram -s {input} -o {output}'


#######################
######### SV ##########

rule prep_sv_vcf:
    input:
        manta_vcf = lambda wc: join(batch_by_name[wc.batch].tumor.dirpath, f'{batch_by_name[wc.batch].name}-sv-prioritize-manta.vcf.gz')
    output:
        vcf = '{batch}/structural/{batch}-sv-prioritize-manta.vcf'
    group: "sv_vcf"
    shell:
        'bcftools view -f.,PASS,REJECT,Intergenic,MissingAnn {input.manta_vcf} > {output}'

rule filter_sv_vcf:
    input:
        vcf = rules.prep_sv_vcf.output.vcf
    output:
        vcf = '{batch}/structural/{batch}-sv-prioritize-manta-filter.vcf'
    group: "sv_vcf"
    run:
        tumor_id = VCF(input.vcf).samples.index(batch_by_name[wildcards.batch].tumor.name)
        shell('bcftools filter -i "(FORMAT/SR[' + str(tumor_id) + ':1]>=5 | FORMAT/PR[' + str(tumor_id) + ':1]>=5) & BPI_AF >= 0.1" {input.vcf} > {output.vcf}')

#### Bring in the prioritized SV calls from Manta. This should also include a basic plot at some stage.
rule prep_sv_tsv:
    input:
        sv_prio = lambda wc: join(batch_by_name[wc.batch].tumor.dirpath, f'{batch_by_name[wc.batch].name}-sv-prioritize.tsv'),
        vcf = rules.filter_sv_vcf.output.vcf
    output:
        '{batch}/structural/{batch}-sv-prioritize-manta-pass.tsv'
    shell:
        'head -n1 {input.sv_prio} > {output} && '
        'grep manta {input.sv_prio} | grep -f <(cut -f1,2 {input.vcf}) >> {output}'


#### At least for the most conservative manta calls generate a file for viewing in Ribbon ###

rule ribbon_filter_manta:
    input:
        manta_vcf = rules.filter_sv_vcf.output.vcf
    output:
        'work/{batch}/structural/ribbon/manta.vcf'
    group: "ribbon"
    shell:
        'bcftools view {input.manta_vcf} > {output}'

rule ribbon_filter_vcfbedtope_starts:
    input:
        bed = rules.ribbon_filter_manta.output[0],
        fai = ref_fa + '.fai'
    output:
        'work/{batch}/structural/ribbon/manta-starts.bed'
    params:
        vcftobedpe = vcftobedpe
    group: "ribbon"
    shell:
        'cat {input.bed} | {params.vcftobedpe}'
        ' | cut -f 1-3'
        ' | bedtools slop -b 5000 -i stdin -g {input.fai}'
        ' > {output}'

rule ribbon_filter_vcfbedtope_ends:
    input:
        bed = rules.ribbon_filter_manta.output[0],
        fai = ref_fa + '.fai'
    output:
        'work/{batch}/structural/ribbon/manta-ends.bed'
    params:
        vcftobedpe = vcftobedpe
    group: "ribbon"
    shell:
        'cat {input.bed} | {params.vcftobedpe}'
        ' | cut -f 4-6'
        ' | grep -v \'CHROM\''
        ' | bedtools slop -b 5000 -i stdin -g {input.fai}'
        ' > {output}'

rule ribbon:
    input:
        starts = rules.ribbon_filter_vcfbedtope_starts.output[0],
        ends = rules.ribbon_filter_vcfbedtope_ends.output[0]
    output:
        '{batch}/structural/{batch}-sv-prioritize-manta.ribbon.bed'
    params:
        vcftobedpe = vcftobedpe
    group: "ribbon"
    shell:
        'cat {input.starts} {input.ends} | bedtools sort -i stdin | bedtools merge -i stdin > {output}'


#### Convert matna VCF to bedpe ####
rule bedpe:
    input:
        manta_vcf = rules.filter_sv_vcf.output.vcf
    output:
        '{batch}/structural/{batch}-sv-prioritize-manta.bedpe'
    params:
        vcftobedpe = vcftobedpe
    shell:
        'bcftools view {input.manta_vcf}'
        ' | {params.vcftobedpe}'
        ' | cut -f 1-7'
        ' > {output}'


#############

rule structural:
    input:
        expand(rules.bedpe.output, batch=batch_by_name.keys()),
        expand(rules.ribbon.output, batch=batch_by_name.keys()),
        expand(rules.prep_sv_tsv.output, batch=batch_by_name.keys()),
        expand(rules.cnvkit_plot.output, batch=batch_by_name.keys())
    output:
        temp(touch('structural.done'))
