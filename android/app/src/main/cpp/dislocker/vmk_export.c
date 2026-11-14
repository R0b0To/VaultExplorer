/*
 * VaultExplorer addition to the dislocker overlay -- see vmk_export.h.
 * Built inside dislocker_lib so it can use the library's private headers.
 */
#include <string.h>

#include "dislocker/dislocker.priv.h"
#include "dislocker/inouts/inouts.priv.h"
#include "dislocker/metadata/datums.h"
#include "dislocker/vmk_export.h"

size_t dis_export_vmk(dis_context_t ctx, uint8_t* out, size_t out_cap)
{
	if(!ctx || !out)
		return 0;

	datum_key_t* vmk = ctx->io_data.vmk;
	if(!vmk)
		return 0;

	/* The key bytes directly follow the datum_key_t header. */
	const size_t total = vmk->header.datum_size;
	if(total <= sizeof(datum_key_t))
		return 0;

	const size_t key_len = total - sizeof(datum_key_t);
	if(key_len > out_cap)
		return 0;

	memcpy(out, (const uint8_t*)vmk + sizeof(datum_key_t), key_len);
	return key_len;
}
