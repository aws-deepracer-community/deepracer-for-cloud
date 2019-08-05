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
#include <QtWebKitWidgets/QWebView>
#include <QtWidgets/QAction>
#include <QtWidgets/QApplication>
#include <QtWidgets/QButtonGroup>
#include <QtWidgets/QGridLayout>
#include <QtWidgets/QHBoxLayout>
#include <QtWidgets/QHeaderView>
#include <QtWidgets/QLineEdit>
#include <QtWidgets/QMainWindow>
#include <QtWidgets/QMenu>
#include <QtWidgets/QMenuBar>
#include <QtWidgets/QPushButton>
#include <QtWidgets/QStatusBar>
#include <QtWidgets/QTextEdit>
#include <QtWidgets/QVBoxLayout>
#include <QtWidgets/QWidget>

QT_BEGIN_NAMESPACE

class Ui_MainWindow
{
public:
    QAction *actionSave_as_Profile;
    QAction *actionLoad_Profile;
    QWidget *centralWidget;
    QGridLayout *gridLayout;
    QHBoxLayout *horizontalLayout;
    QVBoxLayout *verticalLayout_3;
    QLineEdit *track_name;
    QTextEdit *hyper_parameters;
    QTextEdit *log;
    QVBoxLayout *verticalLayout;
    QPushButton *init_button;
    QPushButton *start_button;
    QPushButton *stop_button;
    QPushButton *save_button;
    QPushButton *restart_button;
    QPushButton *use_pretrained_button;
    QPushButton *refresh_button;
    QPushButton *uploadbutton;
    QPushButton *delete_button;
    QWebView *webView;
    QTextEdit *action_space;
    QTextEdit *reward_function;
    QStatusBar *statusBar;
    QMenuBar *menuBar;
    QMenu *menuFile;
    QMenu *menuEdit;
    QMenu *menuProfiles;

    void setupUi(QMainWindow *MainWindow)
    {
        if (MainWindow->objectName().isEmpty())
            MainWindow->setObjectName(QStringLiteral("MainWindow"));
        MainWindow->resize(1637, 743);
        actionSave_as_Profile = new QAction(MainWindow);
        actionSave_as_Profile->setObjectName(QStringLiteral("actionSave_as_Profile"));
        actionLoad_Profile = new QAction(MainWindow);
        actionLoad_Profile->setObjectName(QStringLiteral("actionLoad_Profile"));
        centralWidget = new QWidget(MainWindow);
        centralWidget->setObjectName(QStringLiteral("centralWidget"));
        gridLayout = new QGridLayout(centralWidget);
        gridLayout->setSpacing(6);
        gridLayout->setContentsMargins(11, 11, 11, 11);
        gridLayout->setObjectName(QStringLiteral("gridLayout"));
        horizontalLayout = new QHBoxLayout();
        horizontalLayout->setSpacing(6);
        horizontalLayout->setObjectName(QStringLiteral("horizontalLayout"));
        horizontalLayout->setContentsMargins(-1, 0, -1, -1);
        verticalLayout_3 = new QVBoxLayout();
        verticalLayout_3->setSpacing(6);
        verticalLayout_3->setObjectName(QStringLiteral("verticalLayout_3"));
        verticalLayout_3->setContentsMargins(0, -1, -1, -1);
        track_name = new QLineEdit(centralWidget);
        track_name->setObjectName(QStringLiteral("track_name"));
        QSizePolicy sizePolicy(QSizePolicy::Expanding, QSizePolicy::Preferred);
        sizePolicy.setHorizontalStretch(0);
        sizePolicy.setVerticalStretch(0);
        sizePolicy.setHeightForWidth(track_name->sizePolicy().hasHeightForWidth());
        track_name->setSizePolicy(sizePolicy);

        verticalLayout_3->addWidget(track_name);

        hyper_parameters = new QTextEdit(centralWidget);
        hyper_parameters->setObjectName(QStringLiteral("hyper_parameters"));

        verticalLayout_3->addWidget(hyper_parameters);

        log = new QTextEdit(centralWidget);
        log->setObjectName(QStringLiteral("log"));

        verticalLayout_3->addWidget(log);


        horizontalLayout->addLayout(verticalLayout_3);

        verticalLayout = new QVBoxLayout();
        verticalLayout->setSpacing(6);
        verticalLayout->setObjectName(QStringLiteral("verticalLayout"));
        init_button = new QPushButton(centralWidget);
        init_button->setObjectName(QStringLiteral("init_button"));
        QSizePolicy sizePolicy1(QSizePolicy::Preferred, QSizePolicy::Preferred);
        sizePolicy1.setHorizontalStretch(0);
        sizePolicy1.setVerticalStretch(0);
        sizePolicy1.setHeightForWidth(init_button->sizePolicy().hasHeightForWidth());
        init_button->setSizePolicy(sizePolicy1);

        verticalLayout->addWidget(init_button);

        start_button = new QPushButton(centralWidget);
        start_button->setObjectName(QStringLiteral("start_button"));
        sizePolicy1.setHeightForWidth(start_button->sizePolicy().hasHeightForWidth());
        start_button->setSizePolicy(sizePolicy1);

        verticalLayout->addWidget(start_button);

        stop_button = new QPushButton(centralWidget);
        stop_button->setObjectName(QStringLiteral("stop_button"));
        sizePolicy1.setHeightForWidth(stop_button->sizePolicy().hasHeightForWidth());
        stop_button->setSizePolicy(sizePolicy1);

        verticalLayout->addWidget(stop_button);

        save_button = new QPushButton(centralWidget);
        save_button->setObjectName(QStringLiteral("save_button"));
        sizePolicy1.setHeightForWidth(save_button->sizePolicy().hasHeightForWidth());
        save_button->setSizePolicy(sizePolicy1);

        verticalLayout->addWidget(save_button);

        restart_button = new QPushButton(centralWidget);
        restart_button->setObjectName(QStringLiteral("restart_button"));
        sizePolicy1.setHeightForWidth(restart_button->sizePolicy().hasHeightForWidth());
        restart_button->setSizePolicy(sizePolicy1);
        restart_button->setMouseTracking(false);

        verticalLayout->addWidget(restart_button);

        use_pretrained_button = new QPushButton(centralWidget);
        use_pretrained_button->setObjectName(QStringLiteral("use_pretrained_button"));
        sizePolicy1.setHeightForWidth(use_pretrained_button->sizePolicy().hasHeightForWidth());
        use_pretrained_button->setSizePolicy(sizePolicy1);

        verticalLayout->addWidget(use_pretrained_button);

        refresh_button = new QPushButton(centralWidget);
        refresh_button->setObjectName(QStringLiteral("refresh_button"));
        sizePolicy1.setHeightForWidth(refresh_button->sizePolicy().hasHeightForWidth());
        refresh_button->setSizePolicy(sizePolicy1);

        verticalLayout->addWidget(refresh_button);

        uploadbutton = new QPushButton(centralWidget);
        uploadbutton->setObjectName(QStringLiteral("uploadbutton"));
        sizePolicy1.setHeightForWidth(uploadbutton->sizePolicy().hasHeightForWidth());
        uploadbutton->setSizePolicy(sizePolicy1);

        verticalLayout->addWidget(uploadbutton);

        delete_button = new QPushButton(centralWidget);
        delete_button->setObjectName(QStringLiteral("delete_button"));
        sizePolicy1.setHeightForWidth(delete_button->sizePolicy().hasHeightForWidth());
        delete_button->setSizePolicy(sizePolicy1);

        verticalLayout->addWidget(delete_button);


        horizontalLayout->addLayout(verticalLayout);


        gridLayout->addLayout(horizontalLayout, 2, 1, 1, 1);

        webView = new QWebView(centralWidget);
        webView->setObjectName(QStringLiteral("webView"));
        sizePolicy1.setHeightForWidth(webView->sizePolicy().hasHeightForWidth());
        webView->setSizePolicy(sizePolicy1);
        webView->setUrl(QUrl(QStringLiteral("about:blank")));

        gridLayout->addWidget(webView, 0, 1, 1, 1);

        action_space = new QTextEdit(centralWidget);
        action_space->setObjectName(QStringLiteral("action_space"));

        gridLayout->addWidget(action_space, 2, 0, 1, 1);

        reward_function = new QTextEdit(centralWidget);
        reward_function->setObjectName(QStringLiteral("reward_function"));

        gridLayout->addWidget(reward_function, 0, 0, 1, 1);

        MainWindow->setCentralWidget(centralWidget);
        statusBar = new QStatusBar(MainWindow);
        statusBar->setObjectName(QStringLiteral("statusBar"));
        MainWindow->setStatusBar(statusBar);
        menuBar = new QMenuBar(MainWindow);
        menuBar->setObjectName(QStringLiteral("menuBar"));
        menuBar->setGeometry(QRect(0, 0, 1637, 39));
        menuFile = new QMenu(menuBar);
        menuFile->setObjectName(QStringLiteral("menuFile"));
        menuEdit = new QMenu(menuBar);
        menuEdit->setObjectName(QStringLiteral("menuEdit"));
        menuProfiles = new QMenu(menuBar);
        menuProfiles->setObjectName(QStringLiteral("menuProfiles"));
        MainWindow->setMenuBar(menuBar);

        menuBar->addAction(menuFile->menuAction());
        menuBar->addAction(menuEdit->menuAction());
        menuBar->addAction(menuProfiles->menuAction());
        menuProfiles->addAction(actionSave_as_Profile);
        menuProfiles->addAction(actionLoad_Profile);

        retranslateUi(MainWindow);

        QMetaObject::connectSlotsByName(MainWindow);
    } // setupUi

    void retranslateUi(QMainWindow *MainWindow)
    {
        MainWindow->setWindowTitle(QApplication::translate("MainWindow", "MainWindow", Q_NULLPTR));
        actionSave_as_Profile->setText(QApplication::translate("MainWindow", "Save as Profile", Q_NULLPTR));
        actionLoad_Profile->setText(QApplication::translate("MainWindow", "Load Profile ", Q_NULLPTR));
        init_button->setText(QApplication::translate("MainWindow", "Init", Q_NULLPTR));
        start_button->setText(QApplication::translate("MainWindow", "Start ", Q_NULLPTR));
        stop_button->setText(QApplication::translate("MainWindow", "Stop", Q_NULLPTR));
        save_button->setText(QApplication::translate("MainWindow", "Save", Q_NULLPTR));
        restart_button->setText(QApplication::translate("MainWindow", "Restart", Q_NULLPTR));
        use_pretrained_button->setText(QApplication::translate("MainWindow", "Pretrained", Q_NULLPTR));
        refresh_button->setText(QApplication::translate("MainWindow", "Refresh", Q_NULLPTR));
        uploadbutton->setText(QApplication::translate("MainWindow", "Upload ", Q_NULLPTR));
        delete_button->setText(QApplication::translate("MainWindow", "Delete", Q_NULLPTR));
        menuFile->setTitle(QApplication::translate("MainWindow", "File", Q_NULLPTR));
        menuEdit->setTitle(QApplication::translate("MainWindow", "Edit", Q_NULLPTR));
        menuProfiles->setTitle(QApplication::translate("MainWindow", "Profiles", Q_NULLPTR));
    } // retranslateUi

};

namespace Ui {
    class MainWindow: public Ui_MainWindow {};
} // namespace Ui

QT_END_NAMESPACE

#endif // UI_MAINWINDOW_H
