# Four 512 KiB chunks of relevant kernel messages, not the entire kernel log.
function rotate( i, source, destination) {
    close(path)
    for (i = 2; i >= 0; i--) {
        source = path (i ? "." i : "")
        destination = path "." (i + 1)
        system("mv -f " source " " destination " 2>/dev/null")
    }
    bytes = 0
}
BEGIN {
    # Account for an existing file when a collector is restarted.
    while ((getline previous < path) > 0) bytes += length(previous) + 1
    close(path)
}
{
    text = tolower($0)
    if (text !~ /fingerprint|vendor[.]fps_hal|cdfinger|silead|silfp|qseecom|qsee.*(fail|error)|genirq.*finger/) next
    # Avoid retaining obvious payload-oriented debug messages.
    if (text ~ /template|featureitem|featuretable|encapsulated|auth.?token|key.?dump|image.?data/) next
    line = substr($0, 1, 16384)
    if (bytes + length(line) + 1 > limit) rotate()
    print line >> path
    fflush(path)
    bytes += length(line) + 1
}
