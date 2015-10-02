/*
 *  Copyright (c) 2015 Erik Doernenburg and contributors
 *
 *  Licensed under the Apache License, Version 2.0 (the "License"); you may
 *  not use these files except in compliance with the License. You may obtain
 *  a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 *  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
 *  License for the specific language governing permissions and limitations
 *  under the License.
 */

#import "OCMBlockArgCaller.h"
#import "NSMethodSignature+OCMAdditions.h"
#import "NSValue+OCMAdditions.h"
#import "OCMFunctionsPrivate.h"

#define OCMSetDefaultArgument(_type, _inv, _at) ({ _type _v = 0; [_inv setArgument:&_v atIndex:_at]; break; })

@implementation OCMBlockArgCaller

- (instancetype)initWithBlockArguments:(NSArray *)someArgs
{
    self = [super init];
    if(self)
    {
        arguments = [someArgs copy];
    }
    return self;
}

- (void)dealloc
{
    [arguments release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    return [self retain];
}

- (NSInvocation *)buildInvocationForBlock:(id)block
{
    
    NSMethodSignature *sig = [NSMethodSignature signatureForBlock:block];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    
    NSUInteger numArgsRequired = sig.numberOfArguments - 1;
    if((arguments != nil) && ([arguments count] != numArgsRequired))
        [NSException raise:NSInvalidArgumentException format:@"Specified too few arguments for block; expected %lu arguments.", (unsigned long) numArgsRequired];

    for(NSUInteger i = 0, j = 1; i < numArgsRequired; ++i, ++j)
    {
        id arg = [arguments objectAtIndex:i];
        char const *typeEncoding = [sig getArgumentTypeAtIndex:j];
        
        if((arg == nil) || [arg isKindOfClass:[NSNull class]])
        {
            
            switch(typeEncoding[0])
            {
                case '@':
                {
                    id nilObj = nil;
                    [inv setArgument:&nilObj atIndex:j];
                    break;
                }
                case '^': OCMSetDefaultArgument(void *, inv, j);
                case 'c': OCMSetDefaultArgument(char, inv, j);
                case 'C': OCMSetDefaultArgument(unsigned char, inv, j);
                case 'B': OCMSetDefaultArgument(bool, inv, j);
                case 's': OCMSetDefaultArgument(short, inv, j);
                case 'S': OCMSetDefaultArgument(unsigned short, inv, j);
                case 'i': OCMSetDefaultArgument(int, inv, j);
                case 'I': OCMSetDefaultArgument(unsigned int, inv, j);
                case 'l': OCMSetDefaultArgument(long, inv, j);
                case 'L': OCMSetDefaultArgument(unsigned long, inv, j);
                case 'q': OCMSetDefaultArgument(long long, inv, j);
                case 'Q': OCMSetDefaultArgument(unsigned long long, inv, j);
                case 'f': OCMSetDefaultArgument(float, inv, j);
                case 'd': OCMSetDefaultArgument(double, inv, j);
                default: [NSException raise:NSInvalidArgumentException format:@"Unable to create default value for type %s. All arguments must be specified for this block.", typeEncoding];
            }

        }
        else if (typeEncoding[0] == '@')
        {
            [inv setArgument:&arg atIndex:j];
        }
        else
        {
            if(![arg isKindOfClass:[NSValue class]])
                [NSException raise:NSInvalidArgumentException format:@"Argument at index %lu should be boxed in NSValue.", (long unsigned)i];
            
            char const *valEncoding = [arg objCType];
            NSUInteger argSize;
            NSGetSizeAndAlignment(typeEncoding, &argSize, NULL);
            void *argBuffer = malloc(argSize);

            if(OCMNumberTypeForObjCType(typeEncoding))
            {
                /// @note If the argument is numerical also check that the value is a number;
                /// if so we allow approximate or lossy conversions using `- (BOOL)getBytes:objCType:`.

                if(!OCMNumberTypeForObjCType(valEncoding))
                    [NSException raise:NSInvalidArgumentException format:@"Argument at %lu must be a number.", (long unsigned)i];
                if(![arg getBytes:argBuffer objCType:typeEncoding])
                    [NSException raise:NSInvalidArgumentException format:@"Could not loosely convert from %s to %s at %lu.", valEncoding, typeEncoding, (long unsigned)i];
            }
            else
            {
                /// @note Here we allow any data pointer to be passed as a void pointer, otherwise
                /// the types must match entirely.
                
                BOOL takesVoidPtr = !strcmp(typeEncoding, "^v") && valEncoding[0] == '^';
                if(!takesVoidPtr && !OCMEqualTypesAllowingOpaqueStructs(typeEncoding, valEncoding))
                    [NSException raise:NSInvalidArgumentException format:@"Argument type mismatch; Block requires %s but argument provided is %s", typeEncoding, valEncoding];
                
                [arg getValue:argBuffer];

            }
            
            [inv setArgument:argBuffer atIndex:j];
            free(argBuffer);
            
        }
    }
    
    return inv;
}

- (void)handleArgument:(id)arg
{
    if(arg)
    {
        NSInvocation *inv = [self buildInvocationForBlock:arg];
        [inv invokeWithTarget:arg];
    }
}

@end
