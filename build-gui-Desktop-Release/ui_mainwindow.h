/********************************************************************************
** Form generated from reading UI file 'mainwindow.ui'
**
** Created by: Qt User Interface Compiler version 5.9.5
**
** WARNING! All changes made in this file will be lost when recompiling UI file!
********************************************************************************/

#ifndef UI_MAINWINDOW_H
#define UI_MAINWINDOW_H

#include <QtCore/QVariant>
#include <QtWidgets/QAction>
#include <QtWidgets/QApplication>
#include <QtWidgets/QButtonGroup>
#include <QtWidgets/QGridLayout>
#include <QtWidgets/QHeaderView>
#include <QtWidgets/QLineEdit>
#include <QtWidgets/QMainWindow>
#include <QtWidgets/QPushButton>
#include <QtWidgets/QStatusBar>
#include <QtWidgets/QTextEdit>
#include <QtWidgets/QToolBar>
#include <QtWidgets/QVBoxLayout>
#include <QtWidgets/QWidget>
#include "qwt_plot.h"

QT_BEGIN_NAMESPACE

class Ui_MainWindow
{
public:
    QWidget *centralWidget;
    QGridLayout *gridLayout;
    QVBoxLayout *verticalLayout;
    QPushButton *init_button;
    QPushButton *start_button;
    QPushButton *stop_button;
    QPushButton *save_button;
    QPushButton *restart_button;
    QPushButton *refresh_button;
    QPushButton *uploadbutton;
    QPushButton *delete_button;
    QTextEdit *reward_function;
    QTextEdit *action_space;
    QVBoxLayout *verticalLayout_3;
    QLineEdit *track_name;
    QTextEdit *hyper_parameters;
    QTextEdit *log;
    QwtPlot *reward_plot;
    QToolBar *mainToolBar;
    QStatusBar *statusBar;

    void setupUi(QMainWindow *MainWindow)
    {
        if (MainWindow->objectName().isEmpty())
            MainWindow->setObjectName(QStringLiteral("MainWindow"));
        MainWindow->resize(643, 652);
        centralWidget = new QWidget(MainWindow);
        centralWidget->setObjectName(QStringLiteral("centralWidget"));
        gridLayout = new QGridLayout(centralWidget);
        gridLayout->setSpacing(6);
        gridLayout->setContentsMargins(11, 11, 11, 11);
        gridLayout->setObjectName(QStringLiteral("gridLayout"));
        verticalLayout = new QVBoxLayout();
        verticalLayout->setSpacing(6);
        verticalLayout->setObjectName(QStringLiteral("verticalLayout"));
        init_button = new QPushButton(centralWidget);
        init_button->setObjectName(QStringLiteral("init_button"));
        QSizePolicy sizePolicy(QSizePolicy::Preferred, QSizePolicy::Preferred);
        sizePolicy.setHorizontalStretch(0);
        sizePolicy.setVerticalStretch(0);
        sizePolicy.setHeightForWidth(init_button->sizePolicy().hasHeightForWidth());
        init_button->setSizePolicy(sizePolicy);

        verticalLayout->addWidget(init_button);

        start_button = new QPushButton(centralWidget);
        start_button->setObjectName(QStringLiteral("start_button"));
        sizePolicy.setHeightForWidth(start_button->sizePolicy().hasHeightForWidth());
        start_button->setSizePolicy(sizePolicy);

        verticalLayout->addWidget(start_button);

        stop_button = new QPushButton(centralWidget);
        stop_button->setObjectName(QStringLiteral("stop_button"));
        sizePolicy.setHeightForWidth(stop_button->sizePolicy().hasHeightForWidth());
        stop_button->setSizePolicy(sizePolicy);

        verticalLayout->addWidget(stop_button);

        save_button = new QPushButton(centralWidget);
        save_button->setObjectName(QStringLiteral("save_button"));
        sizePolicy.setHeightForWidth(save_button->sizePolicy().hasHeightForWidth());
        save_button->setSizePolicy(sizePolicy);

        verticalLayout->addWidget(save_button);

        restart_button = new QPushButton(centralWidget);
        restart_button->setObjectName(QStringLiteral("restart_button"));
        sizePolicy.setHeightForWidth(restart_button->sizePolicy().hasHeightForWidth());
        restart_button->setSizePolicy(sizePolicy);
        restart_button->setMouseTracking(false);

        verticalLayout->addWidget(restart_button);

        refresh_button = new QPushButton(centralWidget);
        refresh_button->setObjectName(QStringLiteral("refresh_button"));
        sizePolicy.setHeightForWidth(refresh_button->sizePolicy().hasHeightForWidth());
        refresh_button->setSizePolicy(sizePolicy);

        verticalLayout->addWidget(refresh_button);

        uploadbutton = new QPushButton(centralWidget);
        uploadbutton->setObjectName(QStringLiteral("uploadbutton"));
        sizePolicy.setHeightForWidth(uploadbutton->sizePolicy().hasHeightForWidth());
        uploadbutton->setSizePolicy(sizePolicy);

        verticalLayout->addWidget(uploadbutton);

        delete_button = new QPushButton(centralWidget);
        delete_button->setObjectName(QStringLiteral("delete_button"));
        sizePolicy.setHeightForWidth(delete_button->sizePolicy().hasHeightForWidth());
        delete_button->setSizePolicy(sizePolicy);

        verticalLayout->addWidget(delete_button);


        gridLayout->addLayout(verticalLayout, 21, 3, 1, 1);

        reward_function = new QTextEdit(centralWidget);
        reward_function->setObjectName(QStringLiteral("reward_function"));

        gridLayout->addWidget(reward_function, 0, 0, 1, 1);

        action_space = new QTextEdit(centralWidget);
        action_space->setObjectName(QStringLiteral("action_space"));

        gridLayout->addWidget(action_space, 1, 0, 21, 1);

        verticalLayout_3 = new QVBoxLayout();
        verticalLayout_3->setSpacing(6);
        verticalLayout_3->setObjectName(QStringLiteral("verticalLayout_3"));
        track_name = new QLineEdit(centralWidget);
        track_name->setObjectName(QStringLiteral("track_name"));
        QSizePolicy sizePolicy1(QSizePolicy::Expanding, QSizePolicy::Preferred);
        sizePolicy1.setHorizontalStretch(0);
        sizePolicy1.setVerticalStretch(0);
        sizePolicy1.setHeightForWidth(track_name->sizePolicy().hasHeightForWidth());
        track_name->setSizePolicy(sizePolicy1);

        verticalLayout_3->addWidget(track_name);

        hyper_parameters = new QTextEdit(centralWidget);
        hyper_parameters->setObjectName(QStringLiteral("hyper_parameters"));

        verticalLayout_3->addWidget(hyper_parameters);

        log = new QTextEdit(centralWidget);
        log->setObjectName(QStringLiteral("log"));

        verticalLayout_3->addWidget(log);


        gridLayout->addLayout(verticalLayout_3, 21, 2, 1, 1);

        reward_plot = new QwtPlot(centralWidget);
        reward_plot->setObjectName(QStringLiteral("reward_plot"));
        sizePolicy.setHeightForWidth(reward_plot->sizePolicy().hasHeightForWidth());
        reward_plot->setSizePolicy(sizePolicy);

        gridLayout->addWidget(reward_plot, 0, 1, 1, 3);

        MainWindow->setCentralWidget(centralWidget);
        mainToolBar = new QToolBar(MainWindow);
        mainToolBar->setObjectName(QStringLiteral("mainToolBar"));
        MainWindow->addToolBar(Qt::TopToolBarArea, mainToolBar);
        statusBar = new QStatusBar(MainWindow);
        statusBar->setObjectName(QStringLiteral("statusBar"));
        MainWindow->setStatusBar(statusBar);

        retranslateUi(MainWindow);

        QMetaObject::connectSlotsByName(MainWindow);
    } // setupUi

    void retranslateUi(QMainWindow *MainWindow)
    {
        MainWindow->setWindowTitle(QApplication::translate("MainWindow", "MainWindow", Q_NULLPTR));
        init_button->setText(QApplication::translate("MainWindow", "Init", Q_NULLPTR));
        start_button->setText(QApplication::translate("MainWindow", "Start ", Q_NULLPTR));
        stop_button->setText(QApplication::translate("MainWindow", "Stop", Q_NULLPTR));
        save_button->setText(QApplication::translate("MainWindow", "Save", Q_NULLPTR));
        restart_button->setText(QApplication::translate("MainWindow", "Restart", Q_NULLPTR));
        refresh_button->setText(QApplication::translate("MainWindow", "Refresh", Q_NULLPTR));
        uploadbutton->setText(QApplication::translate("MainWindow", "Upload ", Q_NULLPTR));
        delete_button->setText(QApplication::translate("MainWindow", "Delete", Q_NULLPTR));
    } // retranslateUi

};

namespace Ui {
    class MainWindow: public Ui_MainWindow {};
} // namespace Ui

QT_END_NAMESPACE

#endif // UI_MAINWINDOW_H
