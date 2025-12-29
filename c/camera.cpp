#include <iostream>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <stdint.h>
#include <opencv2/opencv.hpp>
#include <vector>
#include <algorithm>

#define HW_REGS_BASE (0xFF200000)
#define HW_REGS_SPAN (0x00200000)
#define RAM_OFFSET   (0x00040000)
#define CTRL_OFFSET  (0x00050000)
#define LED_OFFSET   (0x00003000) 

// --- TUNING PARAMETERS ---
int thresh_val = 85;    
int thickness = 8;      
int glue_amount = 4;    
int exposure_val = 280; 

// Helper: Center of Mass Shift
cv::Mat shift_to_center_of_mass(cv::Mat &src) {
    cv::Moments m = cv::moments(src, true);
    if (m.m00 < 1e-2) return src; 
    double cx = m.m10 / m.m00;
    double cy = m.m01 / m.m00;
    double shift_x = 14.0 - cx;
    double shift_y = 14.0 - cy;
    cv::Mat trans_mat = (cv::Mat_<float>(2, 3) << 1, 0, shift_x, 0, 1, shift_y);
    cv::Mat dst;
    cv::warpAffine(src, dst, trans_mat, src.size());
    return dst;
}

void set_exposure(int val) {
    system("v4l2-ctl -d /dev/video0 -c exposure_auto=1 2> /dev/null");
    char cmd[100];
    sprintf(cmd, "v4l2-ctl -d /dev/video0 -c exposure_absolute=%d 2> /dev/null", val);
    system(cmd);
}

int main() {
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd == -1) { std::cerr << "ERR: /dev/mem\n"; exit(-1); }
    void * virtual_base = mmap(NULL, HW_REGS_SPAN, PROT_READ | PROT_WRITE, MAP_SHARED, fd, HW_REGS_BASE);
    if (virtual_base == MAP_FAILED) { std::cerr << "ERR: mmap\n"; exit(-1); }
    
    volatile uint32_t * ram_ptr  = (volatile uint32_t*)((char *)virtual_base + RAM_OFFSET);
    volatile uint32_t * ctrl_ptr = (volatile uint32_t*)((char *)virtual_base + CTRL_OFFSET);
    volatile uint32_t * led_ptr  = (volatile uint32_t*)((char *)virtual_base + LED_OFFSET);

    cv::VideoCapture cap(0);
    if (!cap.isOpened()) { std::cerr << "ERR: Camera\n"; exit(-1); }
    
    cap.set(cv::CAP_PROP_FRAME_WIDTH, 640);
    cap.set(cv::CAP_PROP_FRAME_HEIGHT, 480);

    set_exposure(exposure_val);

    cv::namedWindow("Live Inference", cv::WINDOW_AUTOSIZE);
    cv::createTrackbar("Threshold", "Live Inference", &thresh_val, 255); 
    cv::createTrackbar("Ink Glue", "Live Inference", &glue_amount, 10); 
    cv::createTrackbar("Thickness", "Live Inference", &thickness, 20);

    cv::Mat frame, crop, gray, blurred, binary, canvas, final_digit;
    cv::Mat dashboard(480, 640, CV_8UC1); 
    
    cv::Rect target_box(220, 140, 200, 200);

    std::cout << "Running V9 (Fixed) - Live Feedback...\n";

    while (true) {
        cap >> frame;
        if (frame.empty()) exit(0);

        crop = frame(target_box).clone(); 

        cv::cvtColor(crop, gray, cv::COLOR_BGR2GRAY);
        cv::GaussianBlur(gray, blurred, cv::Size(5, 5), 0);
        cv::threshold(blurred, binary, thresh_val, 255, cv::THRESH_BINARY_INV);

        int g = std::max(1, glue_amount);
        cv::dilate(binary, binary, cv::getStructuringElement(cv::MORPH_RECT, cv::Size(g, g)));

        std::vector<std::vector<cv::Point> > contours;
        cv::findContours(binary.clone(), contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

        canvas = cv::Mat::zeros(binary.size(), CV_8UC1);
        double maxArea = 0;
        int maxIdx = -1;

        if (!contours.empty()) {
            for (size_t i = 0; i < contours.size(); i++) {
                double area = cv::contourArea(contours[i]);
                if (area > maxArea) { maxArea = area; maxIdx = i; }
            }
        }

        if (maxIdx >= 0 && maxArea > 50) { 
            cv::drawContours(canvas, contours, maxIdx, cv::Scalar(255), thickness); 
        }

        std::vector<std::vector<cv::Point> > clean_contours;
        cv::findContours(canvas.clone(), clean_contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

        final_digit = cv::Mat::zeros(28, 28, CV_8UC1);
        
        if (!clean_contours.empty()) {
             cv::Rect boundRect = cv::boundingRect(clean_contours[0]);
             cv::Mat digit_roi = canvas(boundRect);

             float scale = 20.0f / std::max(boundRect.width, boundRect.height);
             int newWidth = std::max(1, (int)(boundRect.width * scale));
             int newHeight = std::max(1, (int)(boundRect.height * scale));

             cv::Mat resizedROI;
             cv::resize(digit_roi, resizedROI, cv::Size(newWidth, newHeight), 0, 0, cv::INTER_AREA);

             int dx = (28 - newWidth) / 2;
             int dy = (28 - newHeight) / 2;
             resizedROI.copyTo(final_digit(cv::Rect(dx, dy, newWidth, newHeight)));
             
             final_digit = shift_to_center_of_mass(final_digit);
        }
        
        cv::threshold(final_digit, final_digit, 127, 255, cv::THRESH_BINARY);

        // --- READ FPGA RESULT ---
        uint32_t led_state = *led_ptr; 
        int prediction = led_state & 0x0F; 

        // --- DASHBOARD ---
        cv::rectangle(frame, target_box, cv::Scalar(0, 255, 0), 2);
        
        // --- COMPILER FIX: Use sprintf instead of to_string ---
        char pred_str[50];
        sprintf(pred_str, "FPGA Says: %d", prediction);
        cv::putText(frame, pred_str, cv::Point(20, 50), cv::FONT_HERSHEY_SIMPLEX, 1.2, cv::Scalar(0, 255, 0), 3);

        cv::Mat tl; cv::resize(frame, tl, cv::Size(320, 240));
        cv::cvtColor(tl, tl, cv::COLOR_BGR2GRAY); 
        tl.copyTo(dashboard(cv::Rect(0, 0, 320, 240)));

        cv::Mat tr; cv::resize(binary, tr, cv::Size(320, 240), 0, 0, cv::INTER_NEAREST); 
        tr.copyTo(dashboard(cv::Rect(320, 0, 320, 240)));

        cv::Mat bl; cv::resize(canvas, bl, cv::Size(320, 240));
        bl.copyTo(dashboard(cv::Rect(0, 240, 320, 240)));

        cv::Mat br; cv::resize(final_digit, br, cv::Size(320, 240), 0, 0, cv::INTER_NEAREST);
        br.copyTo(dashboard(cv::Rect(320, 240, 320, 240)));
        
        cv::putText(dashboard, "1. INPUT & RESULT", cv::Point(10, 30), cv::FONT_HERSHEY_SIMPLEX, 0.6, cv::Scalar(255), 2);
        cv::putText(dashboard, "2. Glue View", cv::Point(330, 30), cv::FONT_HERSHEY_SIMPLEX, 0.6, cv::Scalar(127), 2);
        cv::putText(dashboard, "3. Clean Digit", cv::Point(10, 270), cv::FONT_HERSHEY_SIMPLEX, 0.6, cv::Scalar(255), 2);
        cv::putText(dashboard, "4. FPGA Input", cv::Point(330, 270), cv::FONT_HERSHEY_SIMPLEX, 0.6, cv::Scalar(255), 2);

        cv::imshow("Live Inference", dashboard);
        if (cv::waitKey(1) == 27) exit(0);

        // --- FPGA WRITE ---
        cv::Mat padded_image;
        cv::copyMakeBorder(final_digit, padded_image, 2, 2, 2, 2, cv::BORDER_CONSTANT, 0);
        
        int total_pixels = 32 * 32;
        uint32_t packed_word;
        for (int i = 0; i < total_pixels / 4; i++) {
            packed_word = 0;
            packed_word |= ((uint32_t)(padded_image.data[i*4 + 0] / 2));       
            packed_word |= ((uint32_t)(padded_image.data[i*4 + 1] / 2) << 8); 
            packed_word |= ((uint32_t)(padded_image.data[i*4 + 2] / 2) << 16);
            packed_word |= ((uint32_t)(padded_image.data[i*4 + 3] / 2) << 24);
            ram_ptr[i] = packed_word;
        }
        
        *ctrl_ptr = 1; usleep(100); *ctrl_ptr = 0;
        usleep(10000); 
    }
    return 0;
}