## IGV


localrules: igv


# Create BAM and VCF files suitable for moving around easily. Right now this only uses 300 key genes list.
# It also needs to include Sean's cancer predisposition list and create proper Mini-BAMs and VCFs that include regions
# with +/- 1kb around all somatic SNVs, CNVs and SVs.
rule igv_bed:
    input:
        az300 = key_genes_bed,
        small_variant_vcf = rules.somatic_vcf_pon_pass.output[0],
        structural_bed = rules.ribbon.output[0]
    output:
        '{batch}/igv/{batch}-roi.bed'
    shell:
        '{{ '
        'cat {input.az300} | cut -f1-3'
        ' ; '
        'bcftools view -H {input.small_variant_vcf} -Ov | awk -v OFS="\\t" \'{{print $1, $2, $2}}\''
        ' ; '
        'cat {input.structural_bed}'
        ' ; }} '
        ' | bedtools sort -i stdin'
        ' | bedtools merge -i stdin'
        ' > {output}'


rule igv_bam:
    priority: -50
    input:
        bam = lambda wc: getattr(batch_by_name[wc.batch], wc.phenotype).bam,
        bed = rules.igv_bed.output
    output:
        '{batch}/igv/{batch}-{phenotype}.mini.bam'
    benchmark:
        "{batch}/igv/benchmarks/{batch}-{phenotype}.tsv"
    threads:
        max(1, threads_max // (2 * len(batch_by_name)))
    resources:
        mem_mb=lambda wildcards, attempt: attempt * 10000
    shell:
        'samtools view -b -L {input.bed} {input.bam} -@ {threads} > {output}'
        ' && samtools index {output}'


rule igv_upload:
    priority: -50
    input:
        rules.igv_bam.output
    output:
        '{batch}/igv/upload-{phenotype}.done'
    shell:
        upload_proxy + 'aws s3 cp {input} s3://umccr-igv && touch {output}'


rule igv:
    priority: -50
    input:
        expand((rules.igv_upload.output if is_hpc else rules.igv_bam.output),
               phenotype=['tumor', 'normal'], batch=batch_by_name.keys())
    output:
        temp(touch('igv.done'))
