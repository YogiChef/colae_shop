// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:colae_shop/services/sevice.dart'; // สำหรับ styles()

class TimeSelectorWidget extends StatefulWidget {
  final String dayLabel;
  final Function(String day, String? open, String? close) onSave;
  final Function(bool)? onClosed; // ถ้าต้องการ
  final String? currentOpen;
  final String? currentClose;
  final bool currentClosed;

  const TimeSelectorWidget({
    super.key,
    required this.dayLabel,
    required this.onSave,
    this.currentOpen,
    this.currentClose,
    this.onClosed,
    this.currentClosed = false,
  });

  @override
  State<TimeSelectorWidget> createState() => _TimeSelectorWidgetState();
}

class _TimeSelectorWidgetState extends State<TimeSelectorWidget> {
  bool isClosed = false;
  TimeOfDay? _openTime;
  TimeOfDay? _closeTime;

  @override
  void initState() {
    super.initState();
    isClosed = widget.currentClosed;
    _openTime = widget.currentOpen != null
        ? _parseTime(widget.currentOpen!)
        : null;
    _closeTime = widget.currentClose != null
        ? _parseTime(widget.currentClose!)
        : null;
  }

  TimeOfDay? _parseTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        return TimeOfDay(hour: hour, minute: minute);
      }
    } catch (e) {}
    return null;
  }

  Future<void> _selectTime(bool isOpen) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isOpen
          ? (_openTime ?? TimeOfDay.now())
          : (_closeTime ?? TimeOfDay.now()),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            textTheme: Theme.of(context).textTheme.copyWith(
              bodyMedium: styles(fontSize: 12.sp),
              bodyLarge: styles(fontSize: 14.sp),
              headlineSmall: styles(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            timePickerTheme: TimePickerThemeData(
              hourMinuteTextStyle: styles(
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
              hourMinuteColor: Colors.red.shade50,
              backgroundColor: Colors.grey.shade100,
              dialBackgroundColor: Colors.amber.shade200,
              dialTextColor: Colors.pink,
              helpTextStyle: styles(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                color: Colors.black54,
              ),
              dialTextStyle: styles(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              ),
              dayPeriodTextStyle: styles(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              ),
            ),

            dialogTheme: DialogThemeData(
              titleTextStyle: styles(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
            ),
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
        );
      },
    );
    if (picked != null) {
      setState(() {
        // แก้: setState ทันทีเพื่อแสดง local
        if (isOpen) {
          _openTime = picked;
        } else {
          _closeTime = picked;
        }
      });
      final openStr = _formatTime(_openTime);
      final closeStr = _formatTime(_closeTime);
      widget.onSave(
        widget.dayLabel.toLowerCase(),
        openStr,
        closeStr,
      ); // Call parent
      print(
        'Selected timexxx: $openStr - $closeStr for ${widget.dayLabel}',
      ); // Debug
    }
  }

  String? _formatTime(TimeOfDay? time) {
    if (time == null) return null;
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final openText = _openTime != null
        ? _openTime!.format(context)
        : (widget.currentOpen ?? 'เปิด');
    final closeText = _closeTime != null
        ? _closeTime!.format(context)
        : (widget.currentClose ?? 'ปิด');

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
      child: Padding(
        padding: EdgeInsets.only(left: 12.w, right: 12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.dayLabel,
                  style: styles(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: mainColor,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: InkWell(
                    onTap: () => _selectTime(true),
                    child: Container(
                      height: 35.h,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(20.r),
                          bottomLeft: Radius.circular(20.r),
                        ),
                        border: Border(
                          right: BorderSide(
                            color: Colors.grey.shade300,
                            width: 1.w,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 13.sp,
                            color: Colors.black87,
                          ),
                          SizedBox(width: 4.w),
                          Text(
                            openText,
                            style: styles(
                              fontSize: 12.sp,
                              fontWeight: _openTime != null
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => _selectTime(false),
                    child: Container(
                      height: 35.h,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(20.r),
                          bottomRight: Radius.circular(20.r),
                        ),
                        border: Border(
                          right: BorderSide(
                            color: Colors.grey.shade300,
                            width: 1.w,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 13.sp,
                            color: Colors.red.shade700,
                          ),
                          SizedBox(width: 4.w),
                          Text(
                            closeText,
                            style: styles(
                              fontSize: 12.sp,
                              fontWeight: _closeTime != null
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Transform.scale(
                  scale: 0.75.r,

                  child: Switch(
                    padding: EdgeInsets.all(2.w),
                    value: !isClosed, // true = เปิด (switch on)
                    onChanged: (value) {
                      setState(() {
                        isClosed = !value; // value=true=เปิด -> _isClosed=false
                      });
                      widget.onClosed?.call(isClosed); // Call parent
                      if (isClosed) {
                        _openTime = null;
                        _closeTime = null;
                      }
                    },
                    activeThumbColor: mainColor, // สีเมื่อเปิด
                    activeTrackColor: mainColor.withAlpha(50),
                    inactiveThumbColor: Colors.red, // สีเมื่อปิด
                    inactiveTrackColor: Colors.red.withAlpha(50),
                    trackOutlineColor: WidgetStateProperty.all(Colors.grey),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
