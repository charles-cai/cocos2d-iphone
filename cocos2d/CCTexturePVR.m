/*

File: PVRTexture.m
Abstract: The PVRTexture class is responsible for loading .pvr files.

Version: 1.0

Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple Inc.
("Apple") in consideration of your agreement to the following terms, and your
use, installation, modification or redistribution of this Apple software
constitutes acceptance of these terms.  If you do not agree with these terms,
please do not use, install, modify or redistribute this Apple software.

In consideration of your agreement to abide by the following terms, and subject
to these terms, Apple grants you a personal, non-exclusive license, under
Apple's copyrights in this original Apple software (the "Apple Software"), to
use, reproduce, modify and redistribute the Apple Software, with or without
modifications, in source and/or binary forms; provided that if you redistribute
the Apple Software in its entirety and without modifications, you must retain
this notice and the following text and disclaimers in all such redistributions
of the Apple Software.
Neither the name, trademarks, service marks or logos of Apple Inc. may be used
to endorse or promote products derived from the Apple Software without specific
prior written permission from Apple.  Except as expressly stated in this notice,
no other rights or licenses, express or implied, are granted by Apple herein,
including but not limited to any patent rights that may be infringed by your
derivative works or by other works in which the Apple Software may be
incorporated.

The Apple Software is provided by Apple on an "AS IS" basis.  APPLE MAKES NO
WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION THE IMPLIED
WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND OPERATION ALONE OR IN
COMBINATION WITH YOUR PRODUCTS.

IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, MODIFICATION AND/OR
DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER UNDER THEORY OF
CONTRACT, TORT (INCLUDING NEGLIGENCE), STRICT LIABILITY OR OTHERWISE, EVEN IF
APPLE HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Copyright (C) 2008 Apple Inc. All Rights Reserved.

*/

/*
 * Extended PVR formats for cocos2d project ( http://www.cocos2d-iphone.org )
 *	- RGBA8888
 *	- BGRA8888
 *  - RGBA4444
 *  - RGBA5551
 *  - RGB565
 *  - A8
 *  - I8
 *  - AI88
 */

#import <Availability.h>

#import "CCTexturePVR.h"
#import "ccMacros.h"
#import "CCConfiguration.h"
#import "Support/ccUtils.h"
#import "Support/CCFileUtils.h"

#pragma mark -
#pragma mark CCTexturePVR

#define PVR_TEXTURE_FLAG_TYPE_MASK	0xff
#define PVR_TEXTURE_FLAG_FLIPPED_MASK 0x10000

static char gPVRTexIdentifier[4] = "PVR!";

enum
{
	kPVRTextureFlagTypeRGBA_4444= 0x10,
	kPVRTextureFlagTypeRGBA_5551,
	kPVRTextureFlagTypeRGBA_8888,
	kPVRTextureFlagTypeRGB_565,
	kPVRTextureFlagTypeRGB_555,				// unsupported
	kPVRTextureFlagTypeRGB_888,				// unsupported
	kPVRTextureFlagTypeI_8,
	kPVRTextureFlagTypeAI_88,
	kPVRTextureFlagTypePVRTC_2,
	kPVRTextureFlagTypePVRTC_4,	
	kPVRTextureFlagTypeBGRA_8888,
	kPVRTextureFlagTypeA_8,
};

static NSInteger tableFormats[][6] = {
	
	// - PVR texture format
	// - OpenGL internal format
	// - OpenGL format
	// - OpenGL type
	// - bpp
	// - compressed
	{ kPVRTextureFlagTypeRGBA_4444, GL_RGBA,	GL_RGBA, GL_UNSIGNED_SHORT_4_4_4_4,	16, NO	},
	{ kPVRTextureFlagTypeRGBA_5551, GL_RGBA,	GL_RGBA, GL_UNSIGNED_SHORT_5_5_5_1,	16, NO	},
	{ kPVRTextureFlagTypeRGBA_8888, GL_RGBA,	GL_RGBA, GL_UNSIGNED_BYTE,			32, NO	},
	{ kPVRTextureFlagTypeRGB_565,	GL_RGB,		GL_RGB,	 GL_UNSIGNED_SHORT_5_6_5,	16, NO	},
	{ kPVRTextureFlagTypeI_8,		GL_LUMINANCE,	GL_LUMINANCE,	GL_UNSIGNED_BYTE,			8,	NO	},
	{ kPVRTextureFlagTypeAI_88,		GL_LUMINANCE_ALPHA,	GL_LUMINANCE_ALPHA, GL_UNSIGNED_BYTE,	16,	NO	},
#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED
	{ kPVRTextureFlagTypePVRTC_2,	GL_COMPRESSED_RGBA_PVRTC_2BPPV1_IMG, -1, -1,	2,	YES },
	{ kPVRTextureFlagTypePVRTC_4,	GL_COMPRESSED_RGBA_PVRTC_4BPPV1_IMG, -1, -1,	4,	YES	},
#endif // iphone only
	{ kPVRTextureFlagTypeBGRA_8888, GL_RGBA,	GL_BGRA, GL_UNSIGNED_BYTE,			32,	NO	},
	{ kPVRTextureFlagTypeA_8,		GL_ALPHA,	GL_ALPHA,	GL_UNSIGNED_BYTE,		8,	NO	},
};
#define MAX_TABLE_ELEMENTS (sizeof(tableFormats) / sizeof(tableFormats[0]))

enum {
	kCCInternalPVRTextureFormat,
	kCCInternalOpenGLInternalFormat,
	kCCInternalOpenGLFormat,
	kCCInternalOpenGLType,
	kCCInternalBPP,
	kCCInternalCompressedImage,
};

typedef struct _PVRTexHeader
{
	uint32_t headerLength;
	uint32_t height;
	uint32_t width;
	uint32_t numMipmaps;
	uint32_t flags;
	uint32_t dataLength;
	uint32_t bpp;
	uint32_t bitmaskRed;
	uint32_t bitmaskGreen;
	uint32_t bitmaskBlue;
	uint32_t bitmaskAlpha;
	uint32_t pvrTag;
	uint32_t numSurfs;
} PVRTexHeader;


@implementation CCTexturePVR

@synthesize name = name_;
@synthesize width = width_;
@synthesize height = height_;
@synthesize hasAlpha = hasAlpha_;

// cocos2d integration
@synthesize retainName = retainName_;


- (BOOL)unpackPVRData:(NSData *)data
{
	BOOL success = FALSE;
	PVRTexHeader *header = NULL;
	uint32_t flags, pvrTag;
	uint32_t dataLength = 0, dataOffset = 0, dataSize = 0;
	uint32_t blockSize = 0, widthBlocks = 0, heightBlocks = 0;
	uint32_t width = 0, height = 0, bpp = 4;
	uint8_t *bytes = NULL;
	uint32_t formatFlags;
	
	header = (PVRTexHeader *)[data bytes];
	
	pvrTag = CFSwapInt32LittleToHost(header->pvrTag);

	if ((uint32_t)gPVRTexIdentifier[0] != ((pvrTag >>  0) & 0xff) ||
		(uint32_t)gPVRTexIdentifier[1] != ((pvrTag >>  8) & 0xff) ||
		(uint32_t)gPVRTexIdentifier[2] != ((pvrTag >> 16) & 0xff) ||
		(uint32_t)gPVRTexIdentifier[3] != ((pvrTag >> 24) & 0xff))
	{
		return FALSE;
	}
	
	flags = CFSwapInt32LittleToHost(header->flags);
	formatFlags = flags & PVR_TEXTURE_FLAG_TYPE_MASK;
	BOOL flipped = flags & PVR_TEXTURE_FLAG_FLIPPED_MASK;
	if( flipped )
		CCLOG(@"cocos2d: WARNING: Image is flipped. Regenerate it using PVRTexTool");

	if( header->width != ccNextPOT(header->width) || header->height != ccNextPOT(header->height) )
		CCLOG(@"cocos2d: WARNING: PVR NPOT textures are not supported. Regenerate it.");
	
	for( tableFormatIndex_=0; tableFormatIndex_ < MAX_TABLE_ELEMENTS ; tableFormatIndex_++) {
		if( tableFormats[tableFormatIndex_][kCCInternalPVRTextureFormat] == formatFlags ) {
			
			[imageData_ removeAllObjects];
					
			width_ = width = CFSwapInt32LittleToHost(header->width);
			height_ = height = CFSwapInt32LittleToHost(header->height);
			
			if (CFSwapInt32LittleToHost(header->bitmaskAlpha))
				hasAlpha_ = TRUE;
			else
				hasAlpha_ = FALSE;
			
			dataLength = CFSwapInt32LittleToHost(header->dataLength);
			
			bytes = ((uint8_t *)[data bytes]) + sizeof(PVRTexHeader);
			
			// Calculate the data size for each texture level and respect the minimum number of blocks
			while (dataOffset < dataLength)
			{
				switch (formatFlags) {
					case kPVRTextureFlagTypePVRTC_2:
						blockSize = 8 * 4; // Pixel by pixel block size for 2bpp
						widthBlocks = width / 8;
						heightBlocks = height / 4;
						bpp = 2;
						break;
					case kPVRTextureFlagTypePVRTC_4:
						blockSize = 4 * 4; // Pixel by pixel block size for 4bpp
						widthBlocks = width / 4;
						heightBlocks = height / 4;
						bpp = 4;
						break;
					default:
						blockSize = 1;
						widthBlocks = width;
						heightBlocks = height;
						bpp = tableFormats[ tableFormatIndex_][ kCCInternalBPP];
						break;
				}
				
				// Clamp to minimum number of blocks
				if (widthBlocks < 2)
					widthBlocks = 2;
				if (heightBlocks < 2)
					heightBlocks = 2;

				dataSize = widthBlocks * heightBlocks * ((blockSize  * bpp) / 8);
				
				[imageData_ addObject:[NSData dataWithBytes:bytes+dataOffset length:dataSize]];
				
				dataOffset += dataSize;
				
				width = MAX(width >> 1, 1);
				height = MAX(height >> 1, 1);
			}
					  
			success = TRUE;
			break;
		}
	}
	
	if( ! success )
		CCLOG(@"cocos2d: WARNING: Unssupported PVR Pixel Format: 0x%2x", formatFlags);
	
	return success;
}


- (BOOL)createGLTexture
{
	NSUInteger width = width_;
	NSUInteger height = height_;
	NSData *data;
	GLenum err;
	
	if ([imageData_ count] > 0)
	{
		if (name_ != 0)
			glDeleteTextures(1, &name_);
		
		glGenTextures(1, &name_);
		glBindTexture(GL_TEXTURE_2D, name_);
	}

	for (NSUInteger i=0; i < [imageData_ count]; i++)
	{
		GLenum internalFormat = tableFormats[tableFormatIndex_][kCCInternalOpenGLInternalFormat];
		GLenum format = tableFormats[tableFormatIndex_][kCCInternalOpenGLFormat];
		GLenum type = tableFormats[tableFormatIndex_][kCCInternalOpenGLType];
		BOOL compressed = tableFormats[tableFormatIndex_][kCCInternalCompressedImage];
		
		if( compressed && ! [[CCConfiguration sharedConfiguration] supportsPVRTC] ) {
			CCLOG(@"cocos2d: WARNING: PVRTC images is not supported");
			return NO;
		}			
		
		data = [imageData_ objectAtIndex:i];
		if( compressed)
			glCompressedTexImage2D(GL_TEXTURE_2D, i, internalFormat, width, height, 0, [data length], [data bytes]);
		else 
			glTexImage2D(GL_TEXTURE_2D, i, internalFormat, width, height, 0, format, type, [data bytes]);

		
		err = glGetError();
		if (err != GL_NO_ERROR)
		{
			NSLog(@"Error uploading compressed texture level: %u . glError: 0x%04X", (unsigned int)i, err);
			return FALSE;
		}
		
		width = MAX(width >> 1, 1);
		height = MAX(height >> 1, 1);
	}
	
	[imageData_ removeAllObjects];
	
	return TRUE;
}


- (id)initWithContentsOfFile:(NSString *)path
{
	if((self = [super init]))
	{
		NSData *data = [NSData dataWithContentsOfFile:path];
		
		imageData_ = [[NSMutableArray alloc] initWithCapacity:10];
		
		name_ = 0;
		width_ = height_ = 0;
		tableFormatIndex_ = -1;
		hasAlpha_ = FALSE;
		
		retainName_ = NO; // cocos2d integration

		if (!data || ![self unpackPVRData:data] || ![self createGLTexture])
		{
			[self release];
			self = nil;
		}
	}
	
	return self;
}


- (id)initWithContentsOfURL:(NSURL *)url
{
	if (![url isFileURL])
	{
		CCLOG(@"cocos2d: CCPVRTexture: Only files are supported");
		[self release];
		return nil;
	}
	
	return [self initWithContentsOfFile:[url path]];
}


+ (id)pvrTextureWithContentsOfFile:(NSString *)path
{
	return [[[self alloc] initWithContentsOfFile:path] autorelease];
}


+ (id)pvrTextureWithContentsOfURL:(NSURL *)url
{
	if (![url isFileURL])
		return nil;
	
	return [CCTexturePVR pvrTextureWithContentsOfFile:[url path]];
}


- (void)dealloc
{
	CCLOGINFO( @"cocos2d: deallocing %@", self);

	[imageData_ release];
	
	if (name_ != 0 && ! retainName_ )
		glDeleteTextures(1, &name_);
	
	[super dealloc];
}

@end
