#import <Foundation/Foundation.h>
#import <sys/stat.h>
#import <libgen.h>
#import "litehook.h"
#import "LCUtils.h"
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>

mach_header_u *LCGetLoadedImageHeader(int i0, const char* name) {
    for(uint32_t i = i0; i < _dyld_image_count(); ++i) {
        const char* imgName = _dyld_get_image_name(i);
        if(imgName && strcmp(imgName + (strlen(imgName) - strlen(name)), name) == 0) {
            return (struct mach_header_64*)_dyld_get_image_header(i);
        }
    }
    return NULL;
}

struct dyld_all_image_infos *_alt_dyld_get_all_image_infos(void) {
    static struct dyld_all_image_infos *result;
    if (result) {
        return result;
    }
    struct task_dyld_info dyld_info;
    mach_vm_address_t image_infos;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kern_return_t ret;
    ret = task_info(mach_task_self(),
                    TASK_DYLD_INFO,
                    (task_info_t)&dyld_info,
                    &count);
    if (ret != KERN_SUCCESS) {
        return NULL;
    }
    image_infos = dyld_info.all_image_info_addr;
    result = (struct dyld_all_image_infos *)image_infos;
    return result;
}

/*
我不确定是否需要使用
ret = task_info(mach_task_self_,
*/

#if TARGET_OS_SIMULATOR
__attribute__((constructor))
#endif
void *getDyldBase(void) {
    void *dyldBase = (void *)_alt_dyld_get_all_image_infos()->dyldImageLoadAddress;
#if !TARGET_OS_SIMULATOR
    return dyldBase;
#else
    static void *dyldSimBase = NULL;
    if(!dyldSimBase) {
        __block size_t textSize = 0;
        LCParseMachO("/usr/lib/dyld", true, ^(const char *path, struct mach_header_64 *header, int fd, void *filePtr) {
            if(header->cputype != CPU_TYPE_ARM64) return;
            getsegmentdata(header, SEG_TEXT, &textSize);
        });
        NSArray *callStack = [NSThread callStackReturnAddresses];
        for(NSNumber *addr in callStack.reverseObjectEnumerator) {
            uintptr_t addrValue = addr.unsignedLongLongValue;
            if(addrValue < (uintptr_t)dyldBase || addrValue >= (uintptr_t)dyldBase + textSize) {
                dyldSimBase = (void *)(addrValue & ~PAGE_MASK);
                break;
            }
        }
    }
    return dyldSimBase;
#endif
}

NSString *LCParseMachO(const char *path, bool readOnly, LCParseMachOCallback callback) {
    int fd = open(path, readOnly ? O_RDONLY : O_RDWR, (mode_t)readOnly ? 0400 : 0600);
    struct stat s;
    fstat(fd, &s);
    void *map = mmap(NULL, s.st_size, readOnly ? PROT_READ : (PROT_READ | PROT_WRITE), readOnly ? MAP_PRIVATE : MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) {
        return [NSString stringWithFormat:@"Failed to map %s: %s", path, strerror(errno)];
    }

    uint32_t magic = *(uint32_t *)map;
    if (magic == FAT_CIGAM) {
        struct fat_header *header = (struct fat_header *)map;
        struct fat_arch *arch = (struct fat_arch *)(map + sizeof(struct fat_header));
        for (int i = 0; i < OSSwapInt32(header->nfat_arch); i++) {
            if (OSSwapInt32(arch->cputype) == CPU_TYPE_ARM64) {
                callback(path, (struct mach_header_64 *)(map + OSSwapInt32(arch->offset)), fd, map);
            }
            arch = (struct fat_arch *)((void *)arch + sizeof(struct fat_arch));
        }
    } else if (magic == MH_MAGIC_64 || magic == MH_MAGIC) {
        callback(path, (struct mach_header_64 *)map, fd, map);
    } else {
        return @"Not a Mach-O file";
    }

    msync(map, s.st_size, MS_SYNC);
    munmap(map, s.st_size);
    close(fd);
    return nil;
}

uint64_t LCFindSymbolOffset(const char *basePath, const char *symbol) {
#if !TARGET_OS_SIMULATOR
    const char *path = basePath;
#else
    char path[PATH_MAX];
    const char *rootPath = getenv("DYLD_ROOT_PATH") ?: "";
    snprintf(path, sizeof(path), "%s%s", rootPath, basePath);
#endif
    __block uint64_t offset = 0;
    LCParseMachO(path, true, ^(const char *path, struct mach_header_64 *header, int fd, void *filePtr) {
        if(header->cputype != CPU_TYPE_ARM64) return;
        void *result = litehook_find_symbol_file(header, symbol);
        offset = (uint64_t)result - (uint64_t)header;
    });
    NSCAssert(offset != 0, @"Failed to find symbol %s in %s", symbol, path);
    return offset;
}