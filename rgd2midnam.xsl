<?xml version="1.0" ?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
	version="1.0">

<xsl:output method="xml" indent="yes"/>

<xsl:template match="/">
<MIDINameDocument>
	<Author><xsl:value-of select="//librarian/@name"/></Author>
	<MasterDeviceNames>
		<Manufacturer>Rosegarden</Manufacturer>
		<Model><xsl:value-of select="//device/@name"/></Model>
		<CustomDeviceMode Name="{$filename}">
			<ChannelNameSetAssignments>
				<ChannelNameSetAssign Channel="1" NameSet="{$filename}" />
				<ChannelNameSetAssign Channel="2" NameSet="{$filename}" />
				<ChannelNameSetAssign Channel="3" NameSet="{$filename}" />
				<ChannelNameSetAssign Channel="4" NameSet="{$filename}" />
				<ChannelNameSetAssign Channel="5" NameSet="{$filename}" />
				<ChannelNameSetAssign Channel="6" NameSet="{$filename}" />
				<ChannelNameSetAssign Channel="7" NameSet="{$filename}" />
				<ChannelNameSetAssign Channel="8" NameSet="{$filename}" />
				<ChannelNameSetAssign Channel="9" NameSet="{$filename}" />
				<ChannelNameSetAssign Channel="10" NameSet="{$filename}" />
				<ChannelNameSetAssign Channel="11" NameSet="{$filename}" />
				<ChannelNameSetAssign Channel="12" NameSet="{$filename}" />
				<ChannelNameSetAssign Channel="13" NameSet="{$filename}" />
				<ChannelNameSetAssign Channel="14" NameSet="{$filename}" />
				<ChannelNameSetAssign Channel="15" NameSet="{$filename}" />
				<ChannelNameSetAssign Channel="16" NameSet="{$filename}" />
			</ChannelNameSetAssignments>
		</CustomDeviceMode>
		<ChannelNameSet Name="{$filename}" >
			<AvailableForChannels>
				<AvailableChannel Channel="1" Available="true" />
				<AvailableChannel Channel="2" Available="true" />
				<AvailableChannel Channel="3" Available="true" />
				<AvailableChannel Channel="4" Available="true" />
				<AvailableChannel Channel="5" Available="true" />
				<AvailableChannel Channel="6" Available="true" />
				<AvailableChannel Channel="7" Available="true" />
				<AvailableChannel Channel="8" Available="true" />
				<AvailableChannel Channel="9" Available="true" />
				<AvailableChannel Channel="10" Available="true" />
				<AvailableChannel Channel="11" Available="true" />
				<AvailableChannel Channel="12" Available="true" />
				<AvailableChannel Channel="13" Available="true" />
				<AvailableChannel Channel="14" Available="true" />
				<AvailableChannel Channel="15" Available="true" />
				<AvailableChannel Channel="16" Available="true" />
			</AvailableForChannels>
		<xsl:apply-templates/>
		</ChannelNameSet>
	</MasterDeviceNames>
</MIDINameDocument>			
</xsl:template>

<xsl:template match="bank">
			<PatchBank Name="{@name}" >
			  <PatchNameList>
			  	<xsl:apply-templates/>
			  </PatchNameList>
			</PatchBank>
</xsl:template>

<xsl:template match="program">
			    <Patch Number="{@id}" Name="{@name}">
			      <PatchMIDICommands>
				<ControlChange Control="0" Value="{../@msb}" />
				<ControlChange Control="32" Value="{../@lsb}" />
				<ProgramChange Number="{./@id}" />
			      </PatchMIDICommands>
			    </Patch>
</xsl:template>
</xsl:stylesheet>
