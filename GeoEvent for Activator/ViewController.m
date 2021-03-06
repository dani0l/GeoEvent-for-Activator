//
//  ViewController.m
//  GeoEvent for Activator
//
//  Created by hyde on 2014/08/17.
//  Copyright (c) 2014年 hyde. All rights reserved.
//

#import <CoreLocation/CoreLocation.h>
#import "ViewController.h"
#import "GeoFencingItemViewController.h"
#import "AddNewEventViewController.h"

#if !DEBUG
#import <objcipc/objcipc.h>
#import <libactivator/libactivator.h>
#endif

@interface ViewController ()

@end

static NSString * const kEventPrefix = @"geoEvent4Activator";
NSString * const kGEUpdateEvents = @"geoEventSubstrate_UpdateEvents";
NSString * const kGEActivateEvent = @"geoEventSubstrate_ActivateEvent";

@implementation ViewController

- (void)viewWillAppear:(BOOL)animated
{
    NSIndexPath *indexPath = self.tableView.indexPathForSelectedRow;
    if (indexPath) {
        [self.tableView deselectRowAtIndexPath:indexPath animated:animated];
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.navigationItem.title = @"GeoEvent for Activator";
    UIBarButtonItem *addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                               target:self
                                                                               action:@selector(presentAddEventModal:)];
    self.navigationItem.rightBarButtonItem = addButton;
    
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
    
    if (!self.geoFencingItems) {
        self.geoFencingItems = [[NSMutableArray alloc] init];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults registerDefaults:@{@"Monitoring":@NO}];
        self.isGeoFencingMonitoring = [defaults boolForKey:@"Monitoring"];
        NSArray *array = [defaults arrayForKey:@"GeoItems"];
        for (NSDictionary *dict in array) {
            NSString *name = dict[@"Name"];
            NSString *identifier = dict[@"Identifier"];
            NSNumber *enabled = dict[@"Enabled"];
            NSNumber *trigger = dict[@"ExitedTrigger"];
            CLLocationDegrees latitude = [dict[@"Latitude"] doubleValue];
            CLLocationDegrees longitude = [dict[@"Longitude"] doubleValue];
            CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(latitude, longitude);
            CLLocationDistance radius = [dict[@"Radius"] doubleValue];
            CLCircularRegion *region = [[CLCircularRegion alloc] initWithCenter:coordinate radius:radius identifier:identifier];
            region.notifyOnExit = [trigger boolValue];
            region.notifyOnEntry = ![trigger boolValue];
            // new options. need nil check.
            NSString *startFilterTime = dict[@"StartFilterTime"];
            NSString *endFilterTime = dict[@"EndFilterTime"];
            NSNumber *timerFilterEnabled = dict[@"TimeFilterEnabled"];
            startFilterTime = startFilterTime ?: @"00:00";
            endFilterTime = endFilterTime ?: @"00:00";
            timerFilterEnabled = timerFilterEnabled ?: @NO;
            
            [self.geoFencingItems addObject:[@{
                                               @"Name":name,
                                               @"Location":region,
                                               @"Enabled":enabled,
                                               @"ExitedTrigger":trigger,
                                               @"TimeFilterEnabled":timerFilterEnabled,
                                               @"StartFilterTime":startFilterTime,
                                               @"EndFilterTime":endFilterTime
                                               } mutableCopy]];
        }
    }
    if (!self.locationManager) {
        self.locationManager = [[CLLocationManager alloc] init];
        self.locationManager.delegate = self;
    }
    if (self.isGeoFencingMonitoring) {
        [self startEnabledRegionMonitoring];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark -UI action

- (void)presentAddEventModal:(id)sender
{
    AddNewEventViewController *vc = [AddNewEventViewController new];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:navigationController animated:YES completion:^{}];
}

- (void)changeSwitch:(UISwitch *)sender
{
    NSLog(@"main switch changed to = %d", sender.isOn);
    self.isGeoFencingMonitoring = sender.isOn;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:sender.isOn forKey:@"Monitoring"];
    [defaults synchronize];
    
    if (sender.isOn) {
        [self startEnabledRegionMonitoring];
    } else {
        // stop all monitoring.
        for (CLRegion *region in self.locationManager.monitoredRegions)
            [self.locationManager stopMonitoringForRegion:region];
    }
/*    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(11.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{*/
/*        NSLog(@"monitoring regions = %@", self.locationManager.monitoredRegions);*/
/*    });*/
}

- (void)startEnabledRegionMonitoring
{
    for (NSDictionary *item in self.geoFencingItems) {
        CLCircularRegion *region = item[@"Location"];
        if ([item[@"Enabled"] boolValue]) {
            NSLog(@"start monitoring region = %@", region);
            [self.locationManager startMonitoringForRegion:region];
        }
    }
}

#pragma mark -call from modal
- (void)addNewGeoFencingItem:(NSString *)name region:(CLCircularRegion *)region
{
    NSLog(@"Adding new region...");
    region.notifyOnEntry = NO;
    region.notifyOnExit = YES;
    [self.geoFencingItems insertObject:[@{
                                          @"Name":name,
                                          @"Location":region,
                                          @"Enabled":@YES,
                                          @"ExitedTrigger":@YES,
                                          @"TimeFilterEnabled":@NO,
                                          @"StartFilterTime":@"00:00",
                                          @"EndFilterTime":@"00:00"
                                          } mutableCopy] atIndex:0];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:1];
    [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    if (self.isGeoFencingMonitoring)
        [self.locationManager startMonitoringForRegion:region];
    
    // update events IPC to activator.
#if !DEBUG
    [OBJCIPC sendMessageToSpringBoardWithMessageName:kGEUpdateEvents dictionary:nil replyHandler:nil];
#endif
}

#pragma mark -tableView delegate

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cell"];
    }
    if (indexPath.section == 0) {
        cell.textLabel.text = @"Geofencing Enabled";
        UISwitch* sw = [[UISwitch alloc] initWithFrame:CGRectZero];
        [sw addTarget:self action:@selector(changeSwitch:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        sw.on = self.isGeoFencingMonitoring;
    } else {
        cell.textLabel.text = self.geoFencingItems[indexPath.row][@"Name"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        return nil;
    } else {
        return indexPath;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath != 0) {
        GeoFencingItemViewController *vc = [[GeoFencingItemViewController alloc] init];
        vc.selectedRow = indexPath.row;
        [self.navigationController pushViewController:vc animated:YES];
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case 0:
            return 1;
        default:
            return self.geoFencingItems.count;
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        if (self.isGeoFencingMonitoring && self.geoFencingItems[indexPath.row][@"Enabled"]) {
            [self.locationManager stopMonitoringForRegion:self.geoFencingItems[indexPath.row][@"Location"]];
        }
        [self.geoFencingItems removeObjectAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSMutableArray *array = [[defaults arrayForKey:@"GeoItems"] mutableCopy];
        if (array) {
            [array removeObjectAtIndex:indexPath.row];
            [defaults setObject:array forKey:@"GeoItems"];
            [defaults synchronize];
            // update events IPC to activator.
#if !DEBUG
            [OBJCIPC sendMessageToSpringBoardWithMessageName:kGEUpdateEvents dictionary:nil replyHandler:nil];
#endif
        }
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view.
    }
}

#pragma mark -locationManager delegate

- (BOOL)timeFilterForRegion:(CLRegion *)activatedRegion
{
    NSString *startFilterTimeString;
    NSString *endFilterTimeString;
    for (NSDictionary *item in self.geoFencingItems) {
        CLRegion *region = item[@"Location"];
        if ([activatedRegion.identifier isEqualToString:region.identifier]) {
            if (![item[@"TimeFilterEnabled"] boolValue])
                return YES;
            startFilterTimeString = item[@"StartFilterTime"];
            endFilterTimeString = item[@"EndFilterTime"];
            break;
        }
    }
    
    // same mean always available.
    if ([startFilterTimeString isEqualToString:endFilterTimeString])
        return YES;
    
    NSCalendar *gregorian = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
    NSDateComponents *com = [gregorian components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit | NSHourCalendarUnit | NSMinuteCalendarUnit) fromDate:[NSDate date]];
    NSArray *startFilterHourMinute = [startFilterTimeString componentsSeparatedByString:@":"];
    com.hour = [startFilterHourMinute[0] integerValue];
    com.minute = [startFilterHourMinute[1] integerValue];
    NSDate *startDate = [gregorian dateFromComponents:com];
    NSLog(@"startDate = %@", startDate);
    
    NSArray *endFilterHourMinute = [endFilterTimeString componentsSeparatedByString:@":"];
    com.hour = [endFilterHourMinute[0] integerValue];
    com.minute = [endFilterHourMinute[1] integerValue];
    NSDate *endDate = [gregorian dateFromComponents:com];
    NSLog(@"endDate = %@", endDate);
    
    NSDate *now = [NSDate date];
    NSLog(@"now = %@", now);
    
    switch ([startDate compare:endDate]) {
        case NSOrderedAscending:
            // return YES if now date is in range.
            NSLog(@"asc");
            return ([now timeIntervalSinceDate:startDate] > 0 && [now timeIntervalSinceDate:endDate] < 0);
            break;
        case NSOrderedDescending:
            // return YES if now date is not in range.
            NSLog(@"desc");
            return !([now timeIntervalSinceDate:startDate] < 0 && [now timeIntervalSinceDate:endDate] > 0);
            break;
        case NSOrderedSame:
            // it's mean 24h.
            return YES;
    }
}

- (void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region
{
    NSLog(@"Enter %@", region);
#if !DEBUG
    if ([self timeFilterForRegion:region]) {
        NSString *eventName = [kEventPrefix stringByAppendingString:region.identifier];
        [LASharedActivator sendEventToListener:[LAEvent eventWithName:eventName mode:LASharedActivator.currentEventMode]];
        //[OBJCIPC sendMessageToSpringBoardWithMessageName:kGEActivateEvent dictionary:@{@"Identifier":region.identifier} replyHandler:nil];
    }
#endif
}

- (void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region
{
    NSLog(@"Exit %@", region);
#if !DEBUG
    if ([self timeFilterForRegion:region]) {
        NSString *eventName = [kEventPrefix stringByAppendingString:region.identifier];
        [LASharedActivator sendEventToListener:[LAEvent eventWithName:eventName mode:LASharedActivator.currentEventMode]];
        //[OBJCIPC sendMessageToSpringBoardWithMessageName:kGEActivateEvent dictionary:@{@"Identifier":region.identifier} replyHandler:nil];
    }
#endif
}

- (void)locationManager:(CLLocationManager *)manager monitoringDidFailForRegion:(CLRegion *)region withError:(NSError *)error
{
    NSLog(@"region.identifier=%@ error=%@",region.identifier,error);
}

@end
