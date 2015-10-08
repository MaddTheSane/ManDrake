/*
 
 ManDrake - Native open-source Mac OS X man page editor 
 Copyright (C) 2011 Sveinbjorn Thordarson <sveinbjornt@gmail.com>
 
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 
 */


#import "ManDrakeDocument.h"
#import "UKSyntaxColoredTextViewController.H"

@implementation ManDrakeDocument
{
	dispatch_semaphore_t webViewSemaphore;
}

- (instancetype)init
{
    if (self = [super init]) 
	{
		refreshTimer = NULL;
		webViewSemaphore = dispatch_semaphore_create(0);
    }
    return self;
}

- (NSString *)windowNibName
{
    return @"ManDrakeDocument";
}

- (void)windowControllerDidLoadNib:(NSWindowController *) aController
{
	// set up line numbering for text view
	scrollView = [textView enclosingScrollView];
	lineNumberView = [[MarkerLineNumberView alloc] initWithScrollView:scrollView];
    [scrollView setVerticalRulerView:lineNumberView];
    [scrollView setHasHorizontalRuler:NO];
    [scrollView setHasVerticalRuler:YES];
    
    [refreshTypePopupButton selectItemWithTitle: [[NSUserDefaults standardUserDefaults] objectForKey: @"Refresh"]];
	
	// Register for "text changed" notifications of the text storage:
	[[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(textDidChange:)
												 name: NSTextStorageDidProcessEditingNotification
											   object: [textView textStorage]];
		
    [super windowControllerDidLoadNib: aController];
}

#pragma mark Web Preview

- (IBAction)refresh:(id)sender
{	
	// generate preview
	[self drawWebView];
}

- (IBAction)refreshChanged:(id)sender
{
    NSLog(@"REFRESH CHANGED");
    [[NSUserDefaults standardUserDefaults] setObject: [refreshTypePopupButton titleOfSelectedItem] forKey: @"Refresh"];
}



- (void)textDidChange:(NSNotification *)aNotification
{
	NSString *refreshText = [refreshTypePopupButton titleOfSelectedItem];
	
	// use delayed timer
	if ([refreshText isEqualToString: @"delayed"])
	{
		if (refreshTimer != NULL)
		{
			[refreshTimer invalidate];
			refreshTimer = NULL;
		}
		refreshTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(updatePreview) userInfo:nil repeats:NO];
		
	}
	// or else do it for every change
	else if ([refreshText isEqualToString: @"live"])
	{
		[self refresh: self];
	}
}

- (void)drawWebView
{
	[refreshProgressIndicator startAnimation: self];
	// write man text to tmp document
	NSTask *task = [[NSTask alloc] init];
	NSPipe *inPipe = [NSPipe pipe];
	NSPipe *outPipe = [NSPipe pipe];
	NSData *rawData = [textView.string dataUsingEncoding:NSUTF8StringEncoding];
	
	// generate commands to create html from man text using nroff and cat2html
	task.launchPath = @"/usr/bin/nroff";
	task.arguments = @[@"-mandoc"];
	task.standardInput = inPipe;
	task.standardOutput = outPipe;
	task.standardError = [NSFileHandle fileHandleWithNullDevice];
	// run the command
	[task launch];
	[[inPipe fileHandleForWriting] writeData:rawData];
	[[inPipe fileHandleForWriting] closeFile];
	
	dispatch_async(dispatch_get_global_queue(0, 0), ^{
		if (dispatch_semaphore_wait(webViewSemaphore, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC / 3)) < 0) {
			return;
		}

		[task waitUntilExit];
		
		// get the file handle from nroff's output.
		NSFileHandle *fd = outPipe.fileHandleForReading;
		
		// create new pipe for cat2html's output
		NSPipe *pipe = [NSPipe pipe];
		//Create new task object
		NSTask *c2Htask = [[NSTask alloc] init];
		c2Htask.launchPath = [[NSBundle mainBundle] pathForResource: @"cat2html" ofType: NULL];
		c2Htask.standardInput = fd;
		c2Htask.standardOutput = pipe;
		c2Htask.standardError = [NSFileHandle fileHandleWithNullDevice];
		// run the command
		[c2Htask launch];
		[c2Htask waitUntilExit];
		
		NSData *htmlData = [pipe.fileHandleForReading readDataToEndOfFile];

		dispatch_sync(dispatch_get_main_queue(), ^{
			// get the current scroll position of the document view of the web view
			NSScrollView *theScrollView = [[[[webView mainFrame] frameView] documentView] enclosingScrollView];
			NSRect scrollViewBounds = [[theScrollView contentView] bounds];
			currentScrollPosition=scrollViewBounds.origin;
			
			// tell the web view to load the generated data
			[webView.mainFrame loadData:htmlData MIMEType:@"text/html" textEncodingName:@"utf-8" baseURL:nil];
			
			[refreshProgressIndicator stopAnimation: self];
			
			dispatch_semaphore_signal(webViewSemaphore);
		});
	});
}

// delegate method we receive when it's done loading the html file. 
- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
	// restore the scroll position
	[[[[webView mainFrame] frameView] documentView] scrollPoint:currentScrollPosition];
}

- (void)updatePreview
{
	[self refresh: self];
	[refreshTimer invalidate];
	refreshTimer = NULL;
}

#pragma mark UKSyntaxColored stuff

-(NSString*) syntaxDefinitionFilename 
{
	return @"Man";
}

-(NSStringEncoding) stringEncoding 
{
    return NSUTF8StringEncoding;
}

#pragma mark UKSyntaxColoredTextViewDelegate methods

-(NSString *)syntaxDefinitionFilenameForTextViewController: (UKSyntaxColoredTextViewController *)sender 
{
	return @"Man";
}

-(NSDictionary*) syntaxDefinitionDictionaryForTextViewController: (UKSyntaxColoredTextViewController*)sender
{
    NSBundle* theBundle = [NSBundle mainBundle];
    NSDictionary* dict = [NSDictionary dictionaryWithContentsOfFile: [theBundle pathForResource: @"Man" ofType:@"plist"]];
    if (!dict) 
	{
        NSLog(@"Failed to find the syntax dictionary");
    }
    return dict;
}




@end
