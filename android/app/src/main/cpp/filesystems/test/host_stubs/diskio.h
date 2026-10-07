// Host-test stand-in for FatFs's diskio.h. The test defines disk_read() and
// disk_write() over plain image files -- that is the seam where the app would
// decrypt container sectors.
#pragma once
#include "ff.h"
typedef enum { RES_OK = 0, RES_ERROR, RES_WRPRT, RES_NOTRDY, RES_PARERR } DRESULT;
DRESULT disk_read(BYTE pdrv, BYTE* buff, LBA_t sector, UINT count);
DRESULT disk_write(BYTE pdrv, const BYTE* buff, LBA_t sector, UINT count);
