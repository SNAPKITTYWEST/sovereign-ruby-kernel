<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="2.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:sgmt="urn:sovereign:sgmt"
    xmlns:qh="urn:quantum-holographic">

<xsl:output method="xml" indent="yes" encoding="UTF-8"/>

<xsl:template match="/">
  <sgmt:crystallization>
    <xsl:apply-templates select="//agent-submission"/>
  </sgmt:crystallization>
</xsl:template>

<xsl:template match="agent-submission">
  <sgmt:agent-normalized
      agent="{@agent}"
      family="{@family}"
      language="{@language}"
      generation="{@generation}"
      submission="{@submission}">

    <sgmt:metadata>
      <sgmt:objective><xsl:value-of select="normalize-space(objective)"/></sgmt:objective>
      <sgmt:input-count><xsl:value-of select="count(inputs/input)"/></sgmt:input-count>
      <sgmt:fact-count><xsl:value-of select="count(facts/fact)"/></sgmt:fact-count>
      <sgmt:rule-count><xsl:value-of select="count(rules/rule)"/></sgmt:rule-count>
      <sgmt:constraint-count><xsl:value-of select="count(constraints/constraint)"/></sgmt:constraint-count>
      <sgmt:kernel-count><xsl:value-of select="count(kernel-candidates/kernel)"/></sgmt:kernel-count>
    </sgmt:metadata>

    <sgmt:facts>
      <xsl:apply-templates select="facts/fact"/>
    </sgmt:facts>

    <sgmt:rules>
      <xsl:apply-templates select="rules/rule"/>
    </sgmt:rules>

    <sgmt:constraints>
      <xsl:apply-templates select="constraints/constraint"/>
    </sgmt:constraints>

    <sgmt:dependencies>
      <xsl:apply-templates select="dependencies/dependency"/>
    </sgmt:dependencies>

    <sgmt:proofs>
      <xsl:apply-templates select="proof-obligations/obligation"/>
    </sgmt:proofs>

    <sgmt:kernels>
      <xsl:apply-templates select="kernel-candidates/kernel"/>
    </sgmt:kernels>

  </sgmt:agent-normalized>
</xsl:template>

<xsl:template match="fact">
  <sgmt:fact
      predicate="{@predicate}"
      arity="{@arity}"
      confidence="{@confidence}">
    <xsl:value-of select="normalize-space(.)"/>
  </sgmt:fact>
</xsl:template>

<xsl:template match="rule">
  <sgmt:rule id="{@id}">
    <sgmt:head><xsl:value-of select="normalize-space(head)"/></sgmt:head>
    <sgmt:body><xsl:value-of select="normalize-space(body)"/></sgmt:body>
  </sgmt:rule>
</xsl:template>

<xsl:template match="constraint">
  <sgmt:constraint
      id="{@id}"
      domain="{@domain}"
      severity="{@severity}">
    <xsl:value-of select="normalize-space(.)"/>
  </sgmt:constraint>
</xsl:template>

<xsl:template match="dependency">
  <sgmt:edge
      from="{@from}"
      to="{@to}"
      relation="{@relation}"/>
</xsl:template>

<xsl:template match="obligation">
  <sgmt:proof
      id="{@id}"
      prover="{@prover}">
    <xsl:value-of select="normalize-space(.)"/>
  </sgmt:proof>
</xsl:template>

<xsl:template match="kernel">
  <sgmt:kernel
      id="{@id}"
      domain="{@domain}"
      purity="{@purity}">
    <xsl:value-of select="."/>
  </sgmt:kernel>
</xsl:template>

</xsl:stylesheet>
