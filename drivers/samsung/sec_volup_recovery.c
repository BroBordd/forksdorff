// SPDX-License-Identifier: GPL-2.0
/*
 * Hold Volume Up during boot -> reboot into recovery, no USB cable needed.
 *
 * Loaded from the ramdisk after exynos-reboot/sec_reboot (see modules.load),
 * so kernel_restart("recovery") sets the recovery reboot mode properly.
 * Disable at runtime: echo 0 > /sys/module/sec_volup_recovery/parameters/enable
 */
#include <linux/delay.h>
#include <linux/gpio.h>
#include <linux/init.h>
#include <linux/input.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/of.h>
#include <linux/of_gpio.h>
#include <linux/reboot.h>
#include <linux/string.h>
#include <linux/workqueue.h>

#define VOLUP_SAMPLES		5
#define VOLUP_SAMPLE_MS		20
#define VOLUP_START_DELAY_MS	500

static bool enable = true;
module_param(enable, bool, 0644);
MODULE_PARM_DESC(enable, "Reboot to recovery if Volume Up is held at boot");

static int volup_gpio = -1;
static bool volup_active_low;

static void volup_recovery_fn(struct work_struct *work);
static DECLARE_DELAYED_WORK(volup_work, volup_recovery_fn);

static int find_volup_gpio(void)
{
	struct device_node *np, *pp;
	int gpio = -ENODEV;

	np = of_find_node_by_path("/gpio_keys");
	if (!np)
		return -ENODEV;

	for_each_child_of_node(np, pp) {
		enum of_gpio_flags flags;
		u32 code;

		if (of_property_read_u32(pp, "linux,code", &code) || code != KEY_VOLUMEUP)
			continue;

		gpio = of_get_gpio_flags(pp, 0, &flags);
		if (gpio_is_valid(gpio))
			volup_active_low = flags & OF_GPIO_ACTIVE_LOW;
		of_node_put(pp);
		break;
	}
	of_node_put(np);
	return gpio;
}

static bool volup_pressed(void)
{
	return (gpio_get_value(volup_gpio) ? 1 : 0) ^ volup_active_low;
}

/* Skip if we are already booting recovery, so a held key cannot loop */
static bool booting_recovery(void)
{
	struct device_node *np = of_find_node_by_path("/chosen");
	const char *args = NULL;
	bool rec = false;

	if (!np)
		return false;
	if (!of_property_read_string(np, "bootargs", &args) && args)
		rec = strstr(args, "androidboot.mode=recovery") ||
		      strstr(args, "androidboot.boot_recovery=1");
	of_node_put(np);
	return rec;
}

static void volup_recovery_fn(struct work_struct *work)
{
	int i;

	if (!enable || booting_recovery())
		return;

	/* must be held for the whole debounce window */
	for (i = 0; i < VOLUP_SAMPLES; i++) {
		if (!volup_pressed())
			return;
		msleep(VOLUP_SAMPLE_MS);
	}

	pr_info("sec_volup_recovery: Volume Up held at boot, rebooting to recovery\n");
	kernel_restart("recovery");
}

static int __init sec_volup_recovery_init(void)
{
	volup_gpio = find_volup_gpio();
	if (!gpio_is_valid(volup_gpio)) {
		pr_warn("sec_volup_recovery: no Volume Up gpio found (%d), disabled\n", volup_gpio);
		return 0;
	}

	schedule_delayed_work(&volup_work, msecs_to_jiffies(VOLUP_START_DELAY_MS));
	return 0;
}

static void __exit sec_volup_recovery_exit(void)
{
	cancel_delayed_work_sync(&volup_work);
}

module_init(sec_volup_recovery_init);
module_exit(sec_volup_recovery_exit);

MODULE_DESCRIPTION("Hold Volume Up at boot to enter recovery without USB");
MODULE_LICENSE("GPL v2");
