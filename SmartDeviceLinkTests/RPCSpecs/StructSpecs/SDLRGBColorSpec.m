#import <Quick/Quick.h>
#import <Nimble/Nimble.h>

#import "SDLRGBColor.h"

#import "SDLNames.h"

QuickSpecBegin(SDLRGBColorSpec)

describe(@"RGBColor Tests", ^{
    it(@"Should set and get correctly", ^{
        SDLRGBColor *testStruct = [[SDLRGBColor alloc] init];

        testStruct.red = @255;
        testStruct.green = @100;
        testStruct.blue = @0;

        expect(testStruct.red).to(equal(@255));
        expect(testStruct.green).to(equal(@100));
        expect(testStruct.blue).to(equal(@0));
    });

    it(@"Should get correctly when initialized with parameters", ^{
        SDLRGBColor *testStruct = [[SDLRGBColor alloc] initWithRed:0 green:100 blue:255];

        expect(testStruct.red).to(equal(@0));
        expect(testStruct.green).to(equal(@100));
        expect(testStruct.blue).to(equal(@255));
    });

    it(@"Should get correctly when initialized with a color", ^{
        UIColor *testColor = [UIColor colorWithRed:0.0 green:0.393 blue:1.0 alpha:0.0];
        SDLRGBColor *testStruct = [[SDLRGBColor alloc] initWithColor:testColor];

        expect(testStruct.red).to(equal(@0));
        expect(testStruct.green).to(beCloseTo(@100));
        expect(testStruct.blue).to(equal(@255));
    });

    it(@"Should get correctly when initialized with a dict", ^{
        NSDictionary *dict = @{SDLNameRed: @0,
                               SDLNameGreen: @100,
                               SDLNameBlue: @255};
        SDLRGBColor *testStruct = [[SDLRGBColor alloc] initWithDictionary:dict];

        expect(testStruct.red).to(equal(@0));
        expect(testStruct.green).to(equal(@100));
        expect(testStruct.blue).to(equal(@255));
    });

    it(@"Should return nil if not set", ^{
        SDLRGBColor *testStruct = [[SDLRGBColor alloc] init];

        expect(testStruct.red).to(beNil());
        expect(testStruct.green).to(beNil());
        expect(testStruct.blue).to(beNil());
    });
});

QuickSpecEnd
